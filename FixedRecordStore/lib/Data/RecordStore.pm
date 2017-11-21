package Data::RecordStore;

=head1 NAME

Data::RecordStore - Simple and fast record based data store

=head1 SYNPOSIS

use Data::RecordStore;


my $store = Data::RecordStore->open_store( $directory );

my $transaction = $store->create_transaction;

my $data = "TEXT DATA OR BYTES";

my $val   = $store->fetch( $someid );

my $id   = $transaction->stow( $data, $optionalID );

my $new_or_recycled_id = $store->next_id;

$transaction->stow( "MORE DATA", $new_or_recycled_id );

$transaction->delete_record( $someid );
$transaction->recycle( $dead_id );

$transaction->commit;

my $has_object_at_id = $store->has_id( $someid );

$store->empty_recycler;

$store->purge_failed_transaction;

=head1 DESCRIPTION

A simple and fast way to store arbitrary text or byte data.
It is written entirely in perl with no non-core dependencies. It is designed to be
both easy to set up and easy to use.

Transactions allow the RecordStore to protect data. Upon opening, the
store checks if a failed transaction

=head1 LIMITATIONS

Data::RecordStore is not meant to store huge amounts of data.
It will fail if it tries to create a file size greater than the
max allowed by the filesystem. This limitation may be removed in
subsequent versions. This limitation is most important when working
with sets of data that approach the max file size of the system
in question.

This is not written with thread safety in mind, so unexpected behavior
can occur when multiple Data::RecordStore objects open the same directory.
Locking coordination is currently the responsibility of the implementation.

=cut

use strict;
use warnings;

use Fcntl qw( SEEK_SET SEEK_END LOCK_EX LOCK_UN );
use File::Path qw(make_path);
use Data::Dumper;

use vars qw($VERSION);

$VERSION = '3.00';

use constant {
    DIRECTORY    => 0,
    OBJ_INDEX    => 1,
    RECYC_SILO   => 2,
    SILOS        => 3,
    VERSION      => 4,
    TRANS_RECORD => 5,

    RECORD_SIZE      => 1,
    FILE_SIZE        => 2,
    FILE_MAX_RECORDS => 3,
    TMPL             => 4,

    TRA_ACTIVE           => 1, # transaction has been created
    TRA_IN_COMMIT        => 2, # commit has been called, not yet completed
    TRA_IN_ROLLBACK      => 3, # commit has been called, has not yet completed
    TRA_CLEANUP_COMMIT   => 4, # everything in commit has been written, TRA is in process of being removed
    TRA_CLEANUP_ROLLBACK => 5, # everything in commit has been written, TRA is in process of being removed
    TRA_DONE             => 6, # transaction complete. It may be removed.
};


=head1 METHODS

=head2 open_store( directory )

Takes a single argument - a directory, and constructs the data store in it.
The directory must be writeable or creatible. If a RecordStore already exists
there, it opens it, otherwise it creates a new one.

=cut

# alias
sub open { goto &Data::RecordStore::open_store }

sub open_store {
    my( $pkg, $directory ) = @_;

    make_path( "$directory/silos", { error => \my $err } );
    if( @$err ) {
        my( $err ) = values %{ $err->[0] };
        die $err;
    }
    my $obj_db_filename = "$directory/OBJ_INDEX";

    #
    # Find the version of the database.
    #
    my $version;
    my $version_file = "$directory/VERSION";
    my $FH;
    if( -e $version_file ) {
        CORE::open $FH, "<", $version_file;
        $version = <$FH>;
        chomp $version;
    } else {
        #
        # a version file needs to be created. if the database
        # had been created and no version exists, assume it is
        # version 1.
        #
        if( -e $obj_db_filename ) {
            die "opening $directory. A database was found with no version information and is assumed to be an old format. Please run the conversion program.";
        }
        $version = $VERSION;
        CORE::open $FH, ">", $version_file;
        print $FH "$version\n";
    }
    close $FH;

    # # RECORDS ARE int transaction id, int status, process id
    # my $transaction_record =
    #     Data::RecordStore::Silo->open_silo( "IIL", "$dir/TRANS_REC" );
    # if( $transaction_record->entry_count > 0 ) {
    #     my $last_transaction = $transaction_record->last_entry;
    #     my( $tid, $status, $pid ) = @$last_transaction;

    #     # check if pid is active

    #     unless( $pid ) { #is active

    #         if( $status == TRA_WRITE ) {
    #              # is okey, the transaction is complete, just hasn't been removed yet
    #         }
    #     }
    #     die "Incomplete transaction";
    # }

    my $self = [
        $directory,
        Data::RecordStore::Silo->open_silo( "IL", $obj_db_filename ),
        Data::RecordStore::Silo->open_silo( "L", "$directory/RECYC" ),
        [],
        $version,
#        $transaction_record,
    ];

    bless $self, ref( $pkg ) || $pkg;

} #open_store

sub create_transaction {
    my $self = shift;
    Data::RecordStore::Transaction->_create( $self );
}

sub list_transactions {
    my $self = shift;
    my $trans_directory = Data::RecordStore::Silo->open_silo( "ILLI", "$self->[DIRECTORY]/TRANS/META" );
    my @trans;
    my $items = $trans_directory->entry_count;
    for( my $trans_id=$items; $trans_id > 0; $trans_id-- ) {
        my $data = $trans_directory->get_record( $trans_id );
        my $trans = Data::RecordStore::Transaction->_create( $self, $data );
        if( $trans->get_state == TRA_DONE ) {
            $trans_directory->pop; #its done, remove it
        } else {
            push @trans, $trans;
        }
    }
    @trans;
}

=head2 stow( data, optionalID )

This saves the text or byte data to the record store.
If an id is passed in, this saves the data to the record
for that id, overwriting what was there.
If an id is not passed in, it creates a new record store.

Returns the id of the record written to.

=cut

sub stow {
    my( $self, $data, $id ) = @_;

    $id //= $self->next_id;

    $self->_ensure_entry_count( $id ) if $id > 0;

    die "ID must be a positive integer" if $id < 1;

    my $save_size = do { use bytes; length( $data ); };

    # tack on the size of the id (a long or 8 bytes) to the byte count
    $save_size += 8;
    my( $current_silo_id, $current_id_in_silo, $old_silo, $needs_swap );
    if( $self->[OBJ_INDEX]->entry_count > $id ) {

        ( $current_silo_id, $current_id_in_silo ) = @{ $self->[OBJ_INDEX]->get_record( $id ) };

        #
        # Check if this record had been saved before, and that the
        # silo is was in has a large enough record size.
        #
        if ( $current_silo_id ) {
            $old_silo = $self->_get_silo( $current_silo_id );

            warn "object '$id' references silo '$current_silo_id' which does not exist" unless $old_silo;

            # if the data isn't too big or too small for the table, keep it where it is and return
            if ( $old_silo->[RECORD_SIZE] >= $save_size && $old_silo->[RECORD_SIZE] < 3 * $save_size ) {
                $old_silo->put_record( $current_id_in_silo, [$id,$data] );
                return $id;
            }

            #
            # the old silo was not big enough (or missing), so remove its record from
            # there, compacting it if possible
            #
            $needs_swap = 1;
        } #if this already had been saved before
    }

    my $silo_id = 1 + int( log( $save_size ) );

    my $silo = $self->_get_silo( $silo_id );

    my $id_in_silo = $silo->next_id;

    $self->[OBJ_INDEX]->put_record( $id, [ $silo_id, $id_in_silo ] );

    $silo->put_record( $id_in_silo, [ $id, $data ] );

    if( $needs_swap ) {
        $self->_swapout( $old_silo, $current_silo_id, $current_id_in_silo );
    }

    $id;
} #stow

=head2 fetch( id )

Returns the record associated with the ID. If the ID has no
record associated with it, undef is returned.

=cut
sub fetch {
    my( $self, $id ) = @_;

    return undef if $id > $self->[OBJ_INDEX]->entry_count;

    my( $silo_id, $id_in_silo ) = @{ $self->[OBJ_INDEX]->get_record( $id ) };

    return undef unless $silo_id;

    my $silo = $self->_get_silo( $silo_id );

    # skip the included id, just get the data
    ( undef, my $data ) = @{ $silo->get_record( $id_in_silo ) };

    $data;
} #fetch

=head2 entry_count

Returns how many active ids have been assigned in this store.
If an ID was assigned but not used, it still counts towards
the number of entries.

=cut
sub entry_count {
    my $self = shift;
    $self->[OBJ_INDEX]->entry_count - $self->[RECYC_SILO]->entry_count;
} #entry_count

=head2 delete_record( id )

Removes the entry with the given id from the store, freeing up its space.
It does not reuse the id.

=cut

sub delete { goto &Data::RecordStore::delete_record }

sub delete_record {
    my( $self, $del_id ) = @_;
    my( $from_silo_id, $current_id_in_silo ) = @{ $self->[OBJ_INDEX]->get_record( $del_id ) };

    return unless $from_silo_id;

    my $from_silo = $self->_get_silo( $from_silo_id );
    $self->[OBJ_INDEX]->put_record( $del_id, [ 0, 0 ] );
    $self->_swapout( $from_silo, $from_silo_id, $current_id_in_silo );
    1;
} #delete_record

=head2 has_id( id )

  Returns true if an object with this id exists in the record store.

=cut
sub has_id {
    my( $self, $id ) = @_;
    my $ec = $self->entry_count;

    return 0 if $ec < $id || $id < 1;

    my( $silo_id ) = @{ $self->[OBJ_INDEX]->get_record( $id ) };
    $silo_id > 0;
} #has_id


=head2 next_id

This sets up a new empty record and returns the
id for it.

=cut
sub next_id {
    my $self = shift;
    my $next = $self->[RECYC_SILO]->pop;
    return $next->[0] if $next && $next->[0];
    $self->[OBJ_INDEX]->next_id;
}


=head2 empty()

This empties out the entire record store completely.
Use only if you mean it.

=cut
sub empty {
    my $self = shift;
    my $silos = $self->_all_silos;
    $self->[RECYC_SILO]->empty;
    $self->[OBJ_INDEX]->empty;
    for my $silo (@$silos) {
        $silo->empty;
    }
} #empty

#This makes sure there there are at least min_count
#entries in this record store. This creates empty
#records if needed.
sub _ensure_entry_count {
    shift->[OBJ_INDEX]->_ensure_entry_count( shift );
} #_ensure_entry_count

#
# Removes a record from the store. If there was a record at the end of the store
# then move that record to the vacated space, reducing the file size by one record.
#
sub _swapout {
    my( $self, $silo, $silo_id, $vacated_silo_id ) = @_;

    my $last_id = $silo->entry_count;

    if( $vacated_silo_id < $last_id ) {
        my $data = $silo->_copy_record( $last_id - 1, $vacated_silo_id - 1 );
        #
        # update the object db with the new silo index for the moved object id
        #
        my( $moving_id ) = unpack( $silo->[TMPL], $data );

        $self->[OBJ_INDEX]->put_record( $moving_id, [ $silo_id, $vacated_silo_id ] );

        #
        # truncate now that the silo is one record shorter
        #
        $silo->pop;
    }
    elsif( $vacated_silo_id == $last_id ) {
        #
        # this was the last record, so just remove it
        #
        $silo->pop;
    }

} #_swapout


=head2 empty_recycler()

  Clears out all data from the recycler

=cut
sub empty_recycler {
    shift->[RECYC_SILO]->empty;
} #empty_recycler

=head2 recycle( id, keep_data_flag )

  Ads the id to the recycler, so it will be returned when next_id is called.
  This removes the data occupied by the id, freeing up space unles keep_data_flag
  is set to true.

=cut
sub recycle {
    my( $self, $id, $keep_data ) = @_;
    $self->delete_record( $id ) unless $keep_data;
    $self->[RECYC_SILO]->push( [$id] );
} #empty_recycler



#
# Returns a list of all the silos created in this Data::RecordStore
#
sub _all_silos {
    my $self = shift;
    opendir my $DIR, "$self->[DIRECTORY]/silos";
    [ map { /(\d+)_OBJSTORE/; $self->_get_silo($1) } grep { /_OBJSTORE/ } readdir($DIR) ];
} #_all_silos

sub _get_silo {
    my( $self, $silo_index ) = @_;

    if( $self->[SILOS][ $silo_index ] ) {
        return $self->[SILOS][ $silo_index ];
    }

    my $silo_row_size = int( exp $silo_index );

    # storing first the size of the record, then the bytes of the record
    my $silo = Data::RecordStore::Silo->open_silo( "LZ*", "$self->[DIRECTORY]/silos/${silo_index}_OBJSTORE", $silo_row_size, $silo_index );

    $self->[SILOS][ $silo_index ] = $silo;
    $silo;
} #_get_silo

# ----------- end Data::RecordStore


=head1 HELPER PACKAGES

Data::RecordStore relies on two helper packages that are useful in
their own right and are documented here.

=head1 HELPER PACKAGE

Data::RecordStore::Silo

=head1 DESCRIPTION

A fixed record store that uses perl pack and unpack templates to store
identically sized sets of data and uses a single file to do so.

=head1 SYNOPSIS

my $template = "LII"; # perl pack template. See perl pack/unpack.

my $size; #required if the template does not have a definite size, like A*

my $store = Data::RecordStore::Silo->open_silo( $template, $filename, $size );

my $new_id = $store->next_id;

$store->put_record( $id, [ 321421424243, 12, 345 ] );

my $more_data = $store->get_record( $other_id );

my $removed_last = $store->pop;

my $last_id = $store->push( $data_at_the_end );

my $entries = $store->entry_count;

if( $entries < $min ) {

    $store->_ensure_entry_count( $min );

}

$store->emtpy;

$store->unlink_store;

=head1 METHODS

=cut
package Data::RecordStore::Silo;

use strict;
use warnings;
no warnings 'uninitialized';
no warnings 'numeric';

use Fcntl qw( SEEK_SET SEEK_END LOCK_EX LOCK_UN );
use File::Path qw(make_path remove_tree);

use constant {
    DIRECTORY        => 0,
    RECORD_SIZE      => 1,
    FILE_SIZE        => 2,
    FILE_MAX_RECORDS => 3,
    TMPL             => 4,
    SILO_INDEX       => 5,
};

$Data::RecordStore::Silo::MAX_SIZE = 2_000_000_000;

=head2 open_silo( template, filename, record_size, optional_silo_index )

Opens or creates the directory for a group of files
that represent one silo storing records of the given
template and size.
If a size is not given, it calculates the size from
the template, if it can. This will die if a zero byte
record size is given or calculated.

=cut

sub open { goto &Data::RecordStore::Silo::open_silo }

sub open_silo {
    my( $pkg, $template, $directory, $size, $silo_index ) = @_;
    my $class = ref( $pkg ) || $pkg;
    my $template_size = $template =~ /\*/ ? 0 : do { use bytes; length( pack( $template ) ) };
    my $record_size = $size // $template_size;

    die "Data::RecordStore::Silo->open_sile error : given record size does not agree with template size" if $size && $template_size && $template_size != $size;
    die "Data::RecordStore::Silo->open_silo Cannot open a zero record sized fixed store" unless $record_size;
    my $file_max_records = int( $Data::RecordStore::Silo::MAX_SIZE / $record_size );
    if( $file_max_records == 0 ) {
        warn "Opening store of size $record_size which is above the set max size of $Data::RecordStore::Silo::MAX_SIZE. Allowing only one record per file for this size.";
        $file_max_records = 1;
    }
    my $file_max_size = $file_max_records * $record_size;

    unless( -d $directory ) {
        die "Data::RecordStore::Silo->open_silo Error operning record store. $directory exists and is not a directory" if -e $directory;
        make_path( $directory ) or die "Data::RecordStore::Silo->open_silo : Unable to create directory $directory";
    }
    unless( -e "$directory/0" ){
        CORE::open( my $fh, ">", "$directory/0" ) or die "Data::RecordStore::Silo->open_silo : Unable to open '$directory/0' : $!";
        close $fh;
    }
    unless( -w "$directory/0" ){
        die "Data::RecordStore::Silo->open_silo Error operning record store. $directory exists but is not writeable" if -e $directory;
    }

    my $silo = bless [
        $directory,
        $record_size,
        $file_max_size,
        $file_max_records,
        $template,
        $silo_index,
    ], $class;

    $silo;
} #open_silo

=head2 empty

This empties out the database, setting it to zero records.

=cut
sub empty {
    my $self = shift;
    my( $first, @files ) = map { "$self->[DIRECTORY]/$_" } $self->_files;
    truncate $first, 0;
    for my $file (@files) {
        unlink $file;
    }
    undef;
} #empty

=head2

Returns the number of entries in this store.
This is the same as the size of the file divided
by the record size.

=cut
sub entry_count {
    # return how many entries this index has
    my $self = shift;
    my @files = $self->_files;
    my $filesize;
    for my $file (@files) {
        $filesize += -s "$self->[DIRECTORY]/$file";
    }
    int( $filesize / $self->[RECORD_SIZE] );
} #entry_count

=head2 get_record( idx )

Returns an arrayref representing the record with the given id.
The array in question is the unpacked template.

=cut
sub get_record {
    my( $self, $id ) = @_;

    die "Data::RecordStore::Silo->get_record : index $id out of bounds. Store has entry count of ".$self->entry_count if $id > $self->entry_count || $id < 1;

    my( $f_idx, $fh, $file, $file_id ) = $self->_fh( $id );

    sysseek( $fh, $self->[RECORD_SIZE] * $f_idx, SEEK_SET )
        or die "Data::RecordStore::Silo->get_record : error reading id $id at file $file_id at index $f_idx. Could not seek to ($self->[RECORD_SIZE] * $f_idx) : $@ $!";
    my $srv = sysread $fh, my $data, $self->[RECORD_SIZE];
    close $fh;

    defined( $srv )
        or die "Data::RecordStore::Silo->get_record : error reading id $id at file $file_id at index $f_idx. Could not read : $@ $!";

    [unpack( $self->[TMPL], $data )];
} #get_record

=head2 next_id

adds an empty record and returns its id, starting with 1

=cut
sub next_id {
    my( $self ) = @_;
    my $next_id = 1 + $self->entry_count;
    $self->_ensure_entry_count( $next_id );
    $next_id;
} #next_id


=head2 pop

Remove the last record and return it.

=cut
sub pop {
    my( $self ) = @_;

    my $entries = $self->entry_count;
    return undef unless $entries;
    my $ret = $self->get_record( $entries );
    my( $f_idx, $fh, $file ) = $self->_fh( $entries );
    my $new_fs = $f_idx * $self->[RECORD_SIZE];
    if( $new_fs || $file =~ m!/0$! ) {
        truncate $fh, $new_fs;
    } else {
        unlink $file;
    }
    close $fh;

    $ret;
} #pop

=head2 last_entry

Return the last record.

=cut
sub last_entry {
    my( $self ) = @_;

    my $entries = $self->entry_count;
    return undef unless $entries;
    $self->get_record( $entries );
} #last_entry


=head2 push( data )

Add a record to the end of this store. Returns the id assigned
to that record. The data must be a scalar or list reference.
If a list reference, it should conform to the pack template
assigned to this store.

=cut
sub push {
    my( $self, $data ) = @_;
    my $next_id = $self->next_id;

    # the problem is that the second file has stuff in it not sure how
    $self->put_record( $next_id, $data );
    $next_id;
} #push

=head2 push( idx, data )

Saves the data to the record and the record to the filesystem.
The data must be a scalar or list reference.
If a list reference, it should conform to the pack template
assigned to this store.

=cut
sub put_record {
    my( $self, $id, $data ) = @_;

    die "Data::RecordStore::Silo->put_record : index $id out of bounds. Store has entry count of ".$self->entry_count if $id > $self->entry_count || $id < 1;

    my $to_write = pack ( $self->[TMPL], ref $data ? @$data : $data );

    # allows the put_record to grow the data store by no more than one entry
    my $write_size = do { use bytes; length( $to_write ) };

    die "Data::RecordStore::Silo->put_record : record too large" if $write_size > $self->[RECORD_SIZE];

    my( $f_idx, $fh, $file, $file_id ) = $self->_fh( $id );

    sysseek( $fh, $self->[RECORD_SIZE] * ($f_idx), SEEK_SET ) && ( my $swv = syswrite( $fh, $to_write ) ) || die "Data::RecordStore::Silo->put_record : unable to put record id $id at file $file_id index $f_idx : $@ $!";
    close $fh;

    1;
} #put_record

=head2 unlink_store

Removes the file for this record store entirely from the file system.

=cut
sub unlink_store {
    my $self = shift;
    remove_tree( $self->[DIRECTORY] ) // die "Data::RecordStore::Silo->unlink_store: Error unlinking store : $!";
} #unlink_store

#
# This copies a record from one index in the store to an other.
# This returns the data of record so copied. Note : idx designates an index beginning at zero as
# opposed to id, which starts with 1.
#
sub _copy_record {
    my( $self, $from_idx, $to_idx ) = @_;

    die "Data::RecordStore::Silo->_copy_record : from_index $from_idx out of bounds. Store has entry count of ".$self->entry_count if $from_idx >= $self->entry_count || $from_idx < 0;

    die "Data::RecordStore::Silo->_copy_record : to_index $to_idx out of bounds. Store has entry count of ".$self->entry_count if $to_idx >= $self->entry_count || $to_idx < 0;

    my( $from_file_idx, $fh_from ) = $self->_fh($from_idx+1);
    my( $to_file_idx, $fh_to ) = $self->_fh($to_idx+1);
    sysseek $fh_from, $self->[RECORD_SIZE] * ($from_file_idx), SEEK_SET
        or die "Data::RecordStore::Silo->_copy_record could not seek ($self->[RECORD_SIZE] * ($to_idx)) : $@ $!";
    my $srv = sysread $fh_from, my $data, $self->[RECORD_SIZE];
    defined( $srv ) or die "Data::RecordStore::Silo->_copy_record could not read : $@ $!";
    sysseek( $fh_to, $self->[RECORD_SIZE] * $to_file_idx, SEEK_SET ) && ( my $swv = syswrite( $fh_to, $data ) );
    defined( $srv ) or die "Data::RecordStore::Silo->_copy_record could not read : $@ $!";
    $data;
} #_copy_record


#Makes sure the data store has at least as many entries
#as the count given. This creates empty records if needed
#to rearch the target record count.
sub _ensure_entry_count {
    my( $self, $count ) = @_;
    my $needed = $count - $self->entry_count;

    if( $needed > 0 ) {
        my( @files ) = $self->_files;
        my $write_file = $files[$#files];

        my $existing_file_records = int( (-s "$self->[DIRECTORY]/$write_file" ) / $self->[RECORD_SIZE] );
        my $records_needed_to_fill = $self->[FILE_MAX_RECORDS] - $existing_file_records;
        $records_needed_to_fill = $needed if $records_needed_to_fill > $needed;
        if( $records_needed_to_fill > 0 ) {
            # fill the last flie up with \0
            CORE::open( my $fh, "+<", "$self->[DIRECTORY]/$write_file" ) or die "Data::RecordStore::Silo->ensure_entry_count : unable to open '$self->[DIRECTORY]/$write_file' : $!";
            my $nulls = "\0" x ( $records_needed_to_fill * $self->[RECORD_SIZE] );
            (my $pos = sysseek( $fh, 0, SEEK_END )) && (my $wrote = syswrite( $fh, $nulls )) || die "Data::RecordStore::Silo->ensure_entry_count : unable to write blank to '$self->[DIRECTORY]/$write_file' : $!";
            close $fh;
            $needed -= $records_needed_to_fill;
        }
        while( $needed > $self->[FILE_MAX_RECORDS] ) {
            # still needed, so create a new file
            $write_file++;

            die "Data::RecordStore::Silo->ensure_entry_count : file $self->[DIRECTORY]/$write_file already exists" if -e $write_file;
            CORE::open( my $fh, ">", "$self->[DIRECTORY]/$write_file" ) or die "Data::RecordStore::Silo->ensure_entry_count : unable to create '$self->[DIRECTORY]/$write_file' : $!";
            my $nulls = "\0" x ( $self->[FILE_MAX_RECORDS] * $self->[RECORD_SIZE] );
            (my $pos = sysseek( $fh, 0, SEEK_SET )) && (my $wrote = syswrite( $fh, $nulls )) || die "Data::RecordStore::Silo->ensure_entry_count : unable to write blank to '$self->[DIRECTORY]/$write_file' : $!";
            $needed -= $self->[FILE_MAX_RECORDS];
            close $fh;
        }
        if( $needed > 0 ) {
            # still needed, so create a new file
            $write_file++;

            die "Data::RecordStore::Silo->ensure_entry_count : file $self->[DIRECTORY]/$write_file already exists" if -e $write_file;
            CORE::open( my $fh, ">", "$self->[DIRECTORY]/$write_file" ) or die "Data::RecordStore::Silo->ensure_entry_count : unable to create '$self->[DIRECTORY]/$write_file' : $!";
            my $nulls = "\0" x ( $needed * $self->[RECORD_SIZE] );
            (my $pos = sysseek( $fh, 0, SEEK_SET )) && (my $wrote = syswrite( $fh, $nulls )) || die "Data::RecordStore::Silo->ensure_entry_count : unable to write blank to '$self->[DIRECTORY]/$write_file' : $!";
            close $fh;
        }
    }
} #_ensure_entry_count

#
# Takes an insertion id and returns
#   an insertion index for in the file
#   filehandle.
#   filepath/filename
#   which number file this is (0 is the first)
#
sub _fh {
    my( $self, $id ) = @_;

    my @files = $self->_files;
    die "Data::RecordStore::Silo->_fh : No files found for this data store" unless @files;

    my $f_idx;
    if( $id ) {
        $f_idx = int( ($id-1) / $self->[FILE_MAX_RECORDS] );
        if( $f_idx > $#files || $f_idx < 0 ) {
            die "Data::RecordStore::Silo->_fh : requested a non existant file handle ($f_idx, $id)";
        }
    }
    else {
        $f_idx = $#files;
    }

    my $file = $files[$f_idx];
    CORE::open( my $fh, "+<", "$self->[DIRECTORY]/$file" ) or die "Data::RecordStore::Silo->_fhu nable to open '$self->[DIRECTORY]/$file' : $! $?";

    (($id - ($f_idx*$self->[FILE_MAX_RECORDS])) - 1,$fh,"$self->[DIRECTORY]/$file",$f_idx);

} #_fh

#
# Returns the list of filenames of the 'silos' of this store. They are numbers starting with 0
#
sub _files {
    my $self = shift;
    opendir( my $dh, $self->[DIRECTORY] ) or die "Data::RecordStore::Silo->_files : can't open $self->[DIRECTORY]\n";
    my( @files ) = (sort { $a <=> $b } grep { $_ eq '0' || (-s "$self->[DIRECTORY]/$_") > 0 } grep { $_ > 0 || $_ eq '0' } readdir( $dh ) );
    closedir $dh;
    @files;
} #_files


# ----------- end Data::RecordStore::Silo

package Data::RecordStore::Transaction;

use constant {
    ID          => 0,
    PID         => 1,
    UPDATE_TIME => 2,
    STATE       => 3,
    STORE       => 4,
    SILO        => 5,
    CATALOG     => 6,

    TRA_ACTIVE           => 1, # transaction has been created
    TRA_IN_COMMIT        => 2, # commit has been called, not yet completed
    TRA_IN_ROLLBACK      => 3, # commit has been called, has not yet completed
    TRA_CLEANUP_COMMIT   => 4, # everything in commit has been written, TRA is in process of being removed
    TRA_CLEANUP_ROLLBACK => 5, # everything in commit has been written, TRA is in process of being removed
    TRA_DONE             => 6, # transaction complete. It may be removed.

};

our @STATE_LOOKUP = ('Active','In Commit','In Rollback','In Commit Cleanup','In Rollback Cleanup','Done');

#
#
#
sub _create {
    my( $pkg, $record_store, $trans_data ) = @_;

    # transaction id
    # process id
    # update time
    # state
    my $trans_catalog = Data::RecordStore::Silo->open_silo( "ILLI", "$record_store->[Data::RecordStore::DIRECTORY]/TRANS/META" );
    my $trans_id;

    if( $trans_data ) {
        ($trans_id) = @$trans_data;
    }
    else {
        $trans_id = $trans_catalog->next_id;
        $trans_data = [ $trans_id, $$, time, TRA_ACTIVE ];
        $trans_catalog->put_record( $trans_id, $trans_data );
    }

    push @$trans_data, $record_store;

    # action
    # obj id
    # from silo id
    # from record id
    # to silo id
    # to record id
    push @$trans_data, Data::RecordStore::Silo->open_silo(
        "ALILIL",
        "$record_store->[Data::RecordStore::DIRECTORY]/TRANS/instances/$trans_id"
        );
    push @$trans_data, $trans_catalog;

    bless $trans_data, $pkg;

} #_create

sub get_update_time { shift->[UPDATE_TIME] }
sub get_process_id  { shift->[PID] }
sub get_state       { shift->[STATE] }
sub get_id          { shift->[ID] }

sub stow {
    my( $self, $data, $id ) = @_;
    die "Data::RecordStore::Transaction::stow Error : is not active" unless $self->[STATE] == TRA_ACTIVE;
   
    my $trans_silo = $self->[SILO];

    my $store = $self->[STORE];
    $id //= $store->next_id;

    $store->_ensure_entry_count( $id ) if $id > 0;

    die "ID must be a positive integer" if $id < 1;

    my $save_size = do { use bytes; length( $data ); };

    # tack on the size of the id (a long or 8 bytes) to the byte count
    $save_size += 8;
    my( $from_silo_id, $from_record_id ) = ( 0, 0 );
    if( $store->[Data::RecordStore::OBJ_INDEX]->entry_count > $id ) {
        ( $from_silo_id, $from_record_id ) = @{ $store->[Data::RecordStore::OBJ_INDEX]->get_record( $id ) };
    }

    my $to_silo_id = 1 + int( log( $save_size ) );

    my $to_silo = $store->_get_silo( $to_silo_id );

    my $to_record_id = $to_silo->next_id;

    $to_silo->put_record( $to_record_id, [ $id, $data ] );

    my $next_trans_id = $trans_silo->next_id;
    # action (stow)
    # obj id
    # from silo id
    # from silo idx
    # to silo id
    # to silo idx
    $trans_silo->put_record( $next_trans_id,
                             [ 'S', $id, $from_silo_id, $from_record_id, $to_silo_id, $to_record_id ] );

    $id;

} #stow

sub delete_record {
    my( $self, $id_to_delete ) = @_;
    my( $from_silo_id, $from_record_id ) = @{ $self->[STORE]->[Data::RecordStore::OBJ_INDEX]->get_record( $id_to_delete ) };
    my $from_silo = $self->[STORE]->_get_silo( $from_silo_id );
    $from_silo->put_record( $self->[ID],
                            [ 'D', $id_to_delete, $from_silo_id, $from_record_id, 0, 0 ] );
    1;
} #delete_record

sub recycle {
    my( $self, $id_to_recycle ) = @_;
    my( $from_silo_id, $from_record_id ) = @{ $self->[STORE]->[Data::RecordStore::OBJ_INDEX]->get_record( $id_to_recycle ) };
    my $from_silo = $self->[STORE]->_get_silo( $from_silo_id );
    $from_silo->put_record( $self->[ID],
                            [ 'R', $id_to_recycle, $from_silo_id, $from_record_id, 0, 0 ] );
    1;
}

sub commit {
    my $self = shift;

    my $state = $self->get_state;
    die "Cannot commit transaction. Transaction state is ".$STATE_LOOKUP[$state]
        unless $state == TRA_ACTIVE || $state == TRA_IN_COMMIT ||
        $state == TRA_IN_ROLLBACK || $state == TRA_CLEANUP_COMMIT;

    my $store = $self->[STORE];

    my $index        = $store->[Data::RecordStore::OBJ_INDEX];
    my $recycle_silo = $store->[Data::RecordStore::OBJ_INDEX];
    my $dir_silo     = $self->[CATALOG];
    my $trans_silo   = $self->[SILO];

    my $trans_id = $self->[ID];

    $dir_silo->put_record( $trans_id, [ $trans_id, $$, time, TRA_IN_COMMIT ] );
    $self->[STATE] = TRA_IN_COMMIT;
    
    my $actions = $trans_silo->entry_count;

    #
    # Rewire the index to the new silo/location
    #
    for my $a_id (1..$actions) {
        my( $action, $record_id, $from_silo_id, $from_record_id, $to_silo_id, $to_record_id ) =
            @{ $trans_silo->get_record($a_id) };
        
        if( $action eq 'S' ) {
            $index->put_record( $record_id, [ $to_silo_id, $to_record_id ] );
        } else {
            $index->put_record( $record_id, [ 0, 0 ] );
            if( $action eq 'R' ) {
                $recycle_silo->push( [$record_id] );
           }
        }
    }

    $dir_silo->put_record( $trans_id, [ $trans_id, $$, time, TRA_CLEANUP_COMMIT ] );
    $self->[STATE] = TRA_CLEANUP_COMMIT;

    #
    # Cleanup discarded data
    #
    for my $a_id (1..$actions) {
        my( $action, $record_id, $from_silo_id, $from_record_id, $to_silo_id, $to_record_id ) =
            @{ $trans_silo->get_record($a_id) };
        if( $from_silo_id ) {
            # what to do if it comes from nowhere
            my $from_silo = $store->_get_silo( $from_silo_id );
            $store->_swapout( $from_silo, $from_silo_id, $from_record_id );
        }
    }

    $dir_silo->put_record( $trans_id, [ $trans_id, $$, time, TRA_DONE ] );
    $self->[STATE] = TRA_DONE;

    $trans_silo->unlink_store;

} #commit

sub rollback {
    my $self = shift;

    my $state = $self->get_state;
    die "Cannot rollback transaction. Transaction state is ".$STATE_LOOKUP[$state]
        unless $state == TRA_ACTIVE || $state == TRA_IN_COMMIT ||
        $state == TRA_IN_ROLLBACK || $state == TRA_CLEANUP_COMMIT;

    my $store = $self->[STORE];

    my $index        = $store->[Data::RecordStore::OBJ_INDEX];
    my $recycle_silo = $store->[Data::RecordStore::OBJ_INDEX];
    my $dir_silo     = $self->[CATALOG];
    my $trans_silo   = $self->[SILO];
    my $trans_id     = $self->[ID];

    $dir_silo->put_record( $trans_id, [ $trans_id, $$, time, TRA_IN_ROLLBACK ] );
    $self->[STATE] = TRA_IN_ROLLBACK;

    my $actions = $trans_silo->entry_count;

    #
    # Rewire the index to the old silo/location
    #
    for my $a_id (1..$actions) {
        my( $action, $record_id, $from_silo_id, $from_record_id, $to_silo_id, $to_record_id ) =
            @{ $trans_silo->get_record($a_id) };

        if( $from_silo_id ) {
            $index->put_record( $record_id, [ $from_silo_id, $from_record_id ] );
        } else {
            $index->put_record( $record_id, [ 0, 0 ] );
        }
    }

    $dir_silo->put_record( $trans_id, [ $trans_id, $$, time, TRA_CLEANUP_ROLLBACK ] );
    $self->[STATE] = TRA_CLEANUP_ROLLBACK;

    #
    # Cleanup new data
    #
    for my $a_id (1..$actions) {
        my( $action, $record_id, $from_silo_id, $from_record_id, $to_silo_id, $to_record_id ) =
            @{ $trans_silo->get_record($a_id) };

        if( $to_silo_id ) {
            my $to_silo = $store->_get_silo( $to_silo_id );
            $store->_swapout( $to_silo, $to_silo_id, $to_record_id );
        }
    }

    $dir_silo->put_record( $trans_id, [ $trans_id, $$, time, TRA_DONE ] );
    $self->[STATE] = TRA_DONE;

    $trans_silo->unlink_store;

    # if this is the last transaction, remove it from the list
    # of transactions
    if( $trans_id == $dir_silo->entry_count ) {
        $dir_silo->pop;
    }
    
} #rollback

1;

__END__


=head1 AUTHOR
       Eric Wolf        coyocanid@gmail.com

=head1 COPYRIGHT AND LICENSE

       Copyright (c) 2015-2017 Eric Wolf. All rights reserved.  This program is free software; you can redistribute it and/or modify it
       under the same terms as Perl itself.

=head1 VERSION
       Version 3.00  (Nov 21, 2017))

=cut
