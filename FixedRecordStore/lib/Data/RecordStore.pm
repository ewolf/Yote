package Data::RecordStore;

=head1 NAME

Data::RecordStore - Simple and fast record based data store

=head1 SYNPOSIS

use Data::RecordStore;


my $store = Data::RecordStore->open_store( $directory );

my $transaction = $store->create_transaction;

my $data = "TEXT DATA OR BYTES";

my $id    = $transaction->stow( $data, $optionalID );

my $val   = $transaction->fetch( $id );

my $new_or_recycled_id = $transaction->next_id;

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
    RECYC_STORE  => 2,
    STORES       => 3,
    VERSION      => 4,
    TRANS_RECORD => 5,

    RECORD_SIZE => 1,
    TMPL        => 4,

    TRA_ACTIVE  => 0, # transaction has been created
    TRA_COMMIT  => 1, # commit has been called, not yet completed
    TRA_WRITE   => 2, # commit has been called, has not yet completed
    TRA_DONE    => 3, # everything in commit has been written, TRA is in process of being removed

};


=head1 METHODS

=head2 open_store( directory )

Takes a single argument - a directory, and constructs the data store in it.
The directory must be writeable or creatible. If a RecordStore already exists
there, it opens it, otherwise it creates a new one.

=cut
sub open_store {
    my( $pkg, $directory ) = @_;

    make_path( "$directory/stores", { error => \my $err } );
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
        open $FH, "<", $version_file;
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
        open $FH, ">", $version_file;
        print $FH "$version\n";
    }
    close $FH;

    # RECORDS ARE int transaction id, int status, process id
    my $transaction_record = Data::RecordStore::FixedStore->open_fixed_store( "IIL", "$dir/TRANS_REC" );
    if( $transaction_record->entry_count > 0 ) {
        my $last_transaction = $transaction_record->last_entry;
        my( $tid, $status, $pid ) = @$last_transaction;

        # check if pid is active

        unless( $pid ) { #is active
            
            if( $status == TRA_WRITE ) {
                 # is okey, the transaction is complete, just hasn't been removed yet
            }           
        }
        die "Incomplete transaction";
    }
    
    my $self = [
        $directory,
        Data::RecordStore::FixedStore->open_fixed_store( "IL", $obj_db_filename ),
        Data::RecordStore::FixedStore->open_fixed_store( "L", "$directory/RECYC" ),
        [],
        $version,
        $transaction_record,
    ];

    bless $self, ref( $pkg ) || $pkg;

} #open

sub create_transaction {
    my $self = shift;
    Data::RecordStore::Transaction->_create( $self );
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

    if( $self->[OBJ_INDEX]->entry_count > $id ) {

        my( $current_store_id, $current_idx_in_store ) = @{ $self->[OBJ_INDEX]->get_record( $id ) };

        #
        # Check if this record had been saved before, and that the
        # store is was in has a large enough record size.
        #
        if ( $current_store_id ) {
            my $old_store = $self->_get_store( $current_store_id );

            warn "object '$id' references store '$current_store_id' which does not exist" unless $old_store;

            # if the data isn't too big or too small for the table, keep it where it is and return
            if ( $old_store->[RECORD_SIZE] >= $save_size && $old_store->[RECORD_SIZE] < 3 * $save_size ) {
                $old_store->put_record( $current_idx_in_store, [$id,$data] );
                return $id;
            }

            #
            # the old store was not big enough (or missing), so remove its record from
            # there, compacting it if possible
            #
            $self->_swapout( $old_store, $current_store_id, $current_idx_in_store );
        }                       #if this already had been saved before
    }

    my $store_id = 1 + int( log( $save_size ) );

    my $store = $self->_get_store( $store_id );

    my $id_in_store = $store->next_id;

    $self->[OBJ_INDEX]->put_record( $id, [ $store_id, $id_in_store ] );

    $store->put_record( $id_in_store, [ $id, $data ] );

    $id;
} #stow

=head2 fetch( id )

Returns the record associated with the ID. If the ID has no
record associated with it, undef is returned.

=cut
sub fetch {
    my( $self, $id ) = @_;

    return undef if $id > $self->[OBJ_INDEX]->entry_count;

    my( $store_id, $id_in_store ) = @{ $self->[OBJ_INDEX]->get_record( $id ) };

    return undef unless $store_id;

    my $store = $self->_get_store( $store_id );

    # skip the included id, just get the data
    ( undef, my $data ) = @{ $store->get_record( $id_in_store ) };

    $data;
} #fetch

=head2 entry_count

Returns how many active ids have been assigned in this store.
If an ID was assigned but not used, it still counts towards
the number of entries.

=cut
sub entry_count {
    my $self = shift;
    $self->[OBJ_INDEX]->entry_count - $self->[RECYC_STORE]->entry_count;
} #entry_count

=head2 delete( id )

Removes the entry with the given id from the store, freeing up its space.
It does not reuse the id.

=cut
sub delete_record {
    my( $self, $del_id ) = @_;
    my( $from_store_id, $current_idx_in_store ) = @{ $self->[OBJ_INDEX]->get_record( $del_id ) };

    return unless $from_store_id;

    my $from_store = $self->_get_store( $from_store_id );
    $self->_swapout( $from_store, $from_store_id, $current_idx_in_store );
    $self->[OBJ_INDEX]->put_record( $del_id, [ 0, 0 ] );
    1;
} #delete_record

=head2 has_id( id )

  Returns true if an object with this id exists in the record store.

=cut
sub has_id {
    my( $self, $id ) = @_;
    my $ec = $self->entry_count;

    return 0 if $ec < $id || $id < 1;

    my( $store_id ) = @{ $self->[OBJ_INDEX]->get_record( $id ) };
    $store_id > 0;
} #has_id


=head2 next_id

This sets up a new empty record and returns the
id for it.

=cut
sub next_id {
    my $self = shift;
    my $next = $self->[RECYC_STORE]->pop;
    return $next->[0] if $next && $next->[0];
    $self->[OBJ_INDEX]->next_id;
}


=head2 empty()

This empties out the entire record store completely.
Use only if you mean it.

=cut
sub empty {
    my $self = shift;
    my $stores = $self->_all_stores;
    $self->[RECYC_STORE]->empty;
    $self->[OBJ_INDEX]->empty;
    for my $store (@$stores) {
        $store->empty;
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
    my( $self, $store, $store_id, $vacated_store_idx ) = @_;

    my $last_id = $store->entry_count;
    my( $f_idx, $fh, $file ) = $store->_fh($last_id);

    if( $vacated_store_idx < $last_id ) {

        sysseek $fh, $store->[RECORD_SIZE] * ($last_id-1), SEEK_SET
            or die "Swapout could not seek ($store->[RECORD_SIZE] * ($last_id-1)) : $@ $!";
        my $srv = sysread $fh, my $data, $store->[RECORD_SIZE];
        defined( $srv ) or die "Could not read : $@ $!";
        sysseek( $fh, $store->[RECORD_SIZE] * ( $vacated_store_idx - 1 ), SEEK_SET ) && ( my $swv = syswrite( $fh, $data ) );
        defined( $srv ) or die "Could not read : $@ $!";

        #
        # update the object db with the new store index for the moved object id
        #
        my( $moving_id ) = unpack( $store->[TMPL], $data );
        $self->[OBJ_INDEX]->put_record( $moving_id, [ $store_id, $vacated_store_idx ] );
    }

    #
    # truncate now that the store is one record shorter
    #
    truncate $fh, $store->[RECORD_SIZE] * ($last_id-1);

    close $fh;
} #_swapout


=head2 empty_recycler()

  Clears out all data from the recycler

=cut
sub empty_recycler {
    shift->[RECYC_STORE]->empty;
} #empty_recycler

=head2 recycle( id, keep_data_flag )

  Ads the id to the recycler, so it will be returned when next_id is called.
  This removes the data occupied by the id, freeing up space unles keep_data_flag
  is set to true.

=cut
sub recycle {
    my( $self, $id, $keep_data ) = @_;
    $self->delete_record( $id ) unless $keep_data;
    $self->[RECYC_STORE]->push( [$id] );
} #empty_recycler



#
# Returns a list of all the stores created in this Data::RecordStore
#
sub _all_stores {
    my $self = shift;
    opendir my $DIR, "$self->[DIRECTORY]/stores";
    [ map { /(\d+)_OBJSTORE/; $self->_get_store($1) } grep { /_OBJSTORE/ } readdir($DIR) ];
} #_all_stores

sub _get_store {
    my( $self, $store_index ) = @_;

    if( $self->[STORES][ $store_index ] ) {
        return $self->[STORES][ $store_index ];
    }

    my $store_row_size = int( exp $store_index );

    # storing first the size of the record, then the bytes of the record
    my $store = Data::RecordStore::FixedStore->open_fixed_store( "LZ*", "$self->[DIRECTORY]/stores/${store_index}_OBJSTORE", $store_row_size );

    $self->[STORES][ $store_index ] = $store;
    $store;
} #_get_store

# ----------- end Data::RecordStore


=head1 HELPER PACKAGES

Data::RecordStore relies on two helper packages that are useful in
their own right and are documented here.

=head1 HELPER PACKAGE

Data::RecordStore::FixedStore

=head1 DESCRIPTION

A fixed record store that uses perl pack and unpack templates to store
identically sized sets of data and uses a single file to do so.

=head1 SYNOPSIS

my $template = "LII"; # perl pack template. See perl pack/unpack.

my $size; #required if the template does not have a definite size, like A*

my $store = Data::RecordStore::FixedStore->open_fixed_store( $template, $filename, $size );

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
package Data::RecordStore::FixedStore;

use strict;
use warnings;
no warnings 'uninitialized';
no warnings 'numeric';

use Fcntl qw( SEEK_SET SEEK_END LOCK_EX LOCK_UN );
use File::Path qw(make_path);

use constant {
    DIRECTORY        => 0,
    RECORD_SIZE      => 1,
    FILE_SIZE        => 2,
    FILE_MAX_RECORDS => 3,
    TMPL             => 4,
};

$Data::RecordStore::FixedStore::MAX_SIZE = 2_000_000_000;

=head2 open_fixed_store( template, filename, record_size )

Opens or creates the file given as a fixed record
length data store. If a size is not given,
it calculates the size from the template, if it can.
This will die if a zero byte record size is determined.

=cut
sub open_fixed_store {
    my( $pkg, $template, $directory, $size ) = @_;
    my $class = ref( $pkg ) || $pkg;
    my $record_size = $size || do { use bytes; length( pack( $template ) ) };
    my $file_max_records = int( $Data::RecordStore::FixedStore::MAX_SIZE / $record_size );
    if( $file_max_records == 0 ) {
        warn "Opening store of size $record_size which is above the set max size of $Data::RecordStore::FixedStore::MAX_SIZE. Allowing only one record per file for this size.";
        $file_max_records = 1;
    }
    my $file_max_size = $file_max_records * $record_size;

    die "Cannot open a zero record sized fixed store" unless $record_size;

    unless( -d $directory ) {
        die "Error operning record store. $directory exists and is not a directory" if -e $directory;
        make_path( $directory ) or die "Unable to create directory $directory";
    }
    unless( -e "$directory/0" ){
        open( my $fh, ">", "$directory/0" ) or die "Unable to open '$directory/0' : $!";
        close $fh;
    }

    bless [
        $directory,
        $record_size,
        $file_max_size,
        $file_max_records,
        $template,
    ], $class;
} #open_fixed_store

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
    die "get record must be a positive integer" if $id < 1;
    
    my( $f_idx, $fh, $file, $file_id ) = $self->_fh( $id );

    sysseek( $fh, $self->[RECORD_SIZE] * $f_idx, SEEK_SET ) or die "get_record : error reading id $id at file $file_id at index $f_idx. Could not seek to ($self->[RECORD_SIZE] * $f_idx) : $@ $!";
    my $srv = sysread $fh, my $data, $self->[RECORD_SIZE];
    close $fh;

    defined( $srv ) or die "get_record : error reading id $id at file $file_id at index $f_idx. Could not read : $@ $!";

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
    truncate $fh, $f_idx * $self->[RECORD_SIZE];
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

    die "put_record : index $id out of bounds. Store has entry count of ".$self->entry_count if $id > (1+$self->entry_count) || $id < 1;

    my $to_write = pack ( $self->[TMPL], ref $data ? @$data : $data );

    # allows the put_record to grow the data store by no more than one entry

    my( $f_idx, $fh, $file, $file_id ) = $self->_fh( $id );

    sysseek( $fh, $self->[RECORD_SIZE] * ($f_idx), SEEK_SET ) && ( my $swv = syswrite( $fh, $to_write ) ) || die "put_record : unable to put record id $id at file $file_id index $f_idx : $@ $!";
    
    close $fh;

    1;
} #put_record

=head2 unlink_store

Removes the file for this record store entirely from the file system.

=cut
sub unlink_store {
    my $self = shift;
    remove_tree( $self->[DIRECTORY] ) // die "Error unlinking store : $!";
} #unlink_store


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
            open( my $fh, "+<", "$self->[DIRECTORY]/$write_file" ) or die "Unable to open '$self->[DIRECTORY]/$write_file' : $!";
            my $nulls = "\0" x ( $records_needed_to_fill * $self->[RECORD_SIZE] );
            (my $pos = sysseek( $fh, 0, SEEK_END )) && (my $wrote = syswrite( $fh, $nulls )) || die "Unable to write blank to '$self->[DIRECTORY]/$write_file' : $!";
            close $fh;
            $needed -= $records_needed_to_fill;
        }
        while( $needed > $self->[FILE_MAX_RECORDS] ) {
            # still needed, so create a new file
            $write_file++;

            die "File $self->[DIRECTORY]/$write_file already exists" if -e $write_file;
            open( my $fh, ">", "$self->[DIRECTORY]/$write_file" ) or die "Unable to create '$self->[DIRECTORY]/$write_file' : $!";
            my $nulls = "\0" x ( $self->[FILE_MAX_RECORDS] * $self->[RECORD_SIZE] );
            (my $pos = sysseek( $fh, 0, SEEK_SET )) && (my $wrote = syswrite( $fh, $nulls )) || die "Unable to write blank to '$self->[DIRECTORY]/$write_file' : $!";
            $needed -= $self->[FILE_MAX_RECORDS];
            close $fh;
        }
        if( $needed > 0 ) {
            # still needed, so create a new file
            $write_file++;

            die "File $self->[DIRECTORY]/$write_file already exists" if -e $write_file;
            open( my $fh, ">", "$self->[DIRECTORY]/$write_file" ) or die "Unable to create '$self->[DIRECTORY]/$write_file' : $!";
            my $nulls = "\0" x ( $needed * $self->[RECORD_SIZE] );
            (my $pos = sysseek( $fh, 0, SEEK_SET )) && (my $wrote = syswrite( $fh, $nulls )) || die "Unable to write blank to '$self->[DIRECTORY]/$write_file' : $!";
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
    die "No files found for this data store" unless @files;

    my $f_idx;
    if( $id ) {
        $f_idx = int( ($id-1) / $self->[FILE_MAX_RECORDS] );
        if( $f_idx > $#files || $f_idx < 0 ) {
            die "Requested a non existant file handle ($f_idx, $id)";
        }
    }
    else {
        $f_idx = $#files;
    }

    my $file = $files[$f_idx];
    open( my $fh, "+<", "$self->[DIRECTORY]/$file" ) or die "Unable to open '$self->[DIRECTORY]/$file' : $! $?";

    (($id - ($f_idx*$self->[FILE_MAX_RECORDS])) - 1,$fh,"$self->[DIRECTORY]/$file",$f_idx);

} #_fh

#
# Returns the list of filenames of the 'silos' of this store. They are numbers starting with 0
#
sub _files {
    my $self = shift;
    opendir( my $dh, $self->[DIRECTORY] ) or die "Can't open $self->[DIRECTORY]\n";
    my( @files ) = (sort { $a <=> $b } grep { $_ > 0 || $_ eq '0' } readdir( $dh ) );
    closedir $dh;
    @files;
} #_files


# ----------- end Data::RecordStore::FixedStore

package Data::RecordStore::Transaction;

use constant {
    TRA_ACTIVE  => 0, # transaction has been created
    TRA_COMMIT  => 1, # commit has been called, not yet completed
    TRA_WRITE   => 2, # commit has been called, has not yet completed
    TRA_DONE    => 3, # everything in commit has been written, TRA is in process of being removed
};

#
#
#
sub _create {
    my( $pkg, $record_store ) = @_;
    my $dir = $record_store->[DIRECTORY];
    # create transaction record
    # create transaction store
    my $transaction_store = Data::RecordStore::FixedStore->open_fixed_store( "IL", "$dir/TRANS/TRANS_" ),
}

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
