package Data::RecordStore;

=head1 NAME

Data::RecordStore - Simple and fast record based data store

=head1 SYNPOSIS

use Data::RecordStore;


my $store = Data::RecordStore->open_store( $directory );

my $data = "TEXT DATA OR BYTES";

my $id    = $store->stow( $data, $optionalID );

my $val   = $store->fetch( $id );

my $new_or_recycled_id = $store->next_id;

$store->stow( "MORE DATA", $new_or_recycled_id );

my $has_object_at_id = $store->has_id( $someid );

$store->delete( $someid );

$store->empty_recycler;
$store->recycle( $dead_id );

=head1 DESCRIPTION

A simple and fast way to store arbitrary text or byte data.
It is written entirely in perl with no non-core dependencies. It is designed to be
both easy to set up and easy to use.

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

use Fcntl qw( SEEK_SET LOCK_EX LOCK_UN );
use File::Path qw(make_path);
use Data::Dumper;

use vars qw($VERSION);

$VERSION = '2.03';

use constant {
    DIRECTORY   => 0,
    OBJ_INDEX   => 1,
    RECYC_STORE => 2,
    STORES      => 3,
    VERSION     => 4,
    STORE_IDX   => 5,

    TMPL        => 0,
    RECORD_SIZE => 1,
    FILENAME    => 2,
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

    my $self = [
        $directory,
        Data::RecordStore::FixedStore->open_fixed_store( "IL", $obj_db_filename ),
        Data::RecordStore::FixedStore->open_fixed_store( "L", "$directory/RECYC" ),
        [],
        $version,
    ];

    bless $self, ref( $pkg ) || $pkg;

} #open

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

    my( $current_store_id, $current_idx_in_store ) = @{ $self->[OBJ_INDEX]->get_record( $id ) };

    #
    # Check if this record had been saved before, and that the
    # store is was in has a large enough record size.
    #
    if( $current_store_id ) {
        my $old_store = $self->_get_store( $current_store_id );

        warn "object '$id' references store '$current_store_id' which does not exist" unless $old_store;

        # if the data isn't too big or too small for the table, keep it where it is and return
        if( $old_store->[RECORD_SIZE] >= $save_size && $old_store->[RECORD_SIZE] < 3 * $save_size ) {
            $old_store->put_record( $current_idx_in_store, [$id,$data] );
            return $id;
        }

        #
        # the old store was not big enough (or missing), so remove its record from
        # there, compacting it if possible
        #
        $self->_swapout( $old_store, $current_store_id, $current_idx_in_store );
    } #if this already had been saved before

    my $store_id = 1 + int( log( $save_size ) );

    my $store = $self->_get_store( $store_id );

    my $index_in_store = $store->next_id;
    $self->[OBJ_INDEX]->put_record( $id, [ $store_id, $index_in_store ] );

    $store->put_record( $index_in_store, [ $id, $data ] );

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
sub delete {
    my( $self, $del_id ) = @_;
    my( $from_store_id, $current_idx_in_store ) = @{ $self->[OBJ_INDEX]->get_record( $del_id ) };

    return unless $from_store_id;

    my $from_store = $self->_get_store( $from_store_id );
    $self->_swapout( $from_store, $from_store_id, $current_idx_in_store );
    $self->[OBJ_INDEX]->put_record( $del_id, [ 0, 0 ] );
    1;
} #delete

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

    my $last_idx = $store->entry_count;
    my $fh = $store->_filehandle($last_idx);

    if( $vacated_store_idx < $last_idx ) {

        sysseek $fh, $store->[RECORD_SIZE] * ($last_idx-1), SEEK_SET
            or die "Swapout could not seek ($store->[RECORD_SIZE] * ($last_idx-1)) : $@ $!";
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
    truncate $fh, $store->[RECORD_SIZE] * ($last_idx-1);

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
    $self->delete( $id ) unless $keep_data;
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

use Fcntl qw( SEEK_SET LOCK_EX LOCK_UN );
use File::Copy;

use constant {
    TMPL        => 0,
    RECORD_SIZE => 1,
    FILENAME    => 2,
    OBJ_INDEX   => 3,
};

$Data::RecordStore::FixedStore::MAX_SIZE = 2_000_000_000;

=head2 open_fixed_store( template, filename, size )

Opens or creates the file given as a fixed record
length data store. If a size is not given,
it calculates the size from the template, if it can.
This will die if a zero byte record size is determined.

=cut
sub open_fixed_store {
    my( $pkg, $template, $filename, $size ) = @_;
    my $class = ref( $pkg ) || $pkg;
    my $FH;
    my $useSize = $size || do { use bytes; length( pack( $template ) ) };
    die "Cannot open a zero record sized fixed store" unless $useSize;
    unless( -e $filename ) {
        open $FH, ">", $filename or die "Unable to open $filename : $!";
        print $FH "";
        close $FH;
    }
    open $FH, "+<", $filename or die "$@ $!";
    bless [
        $template,
        $useSize,
        $filename,
    ], $class;
} #open

=head2 empty

This empties out the database, setting it to zero records.

=cut
sub empty {
    my $self = shift;
    my $fh = $self->_filehandle;
    truncate $self->[FILENAME], 0;
    undef;
} #empty

#Makes sure the data store has at least as many entries
#as the count given. This creates empty records if needed
#to rearch the target record count.
sub _ensure_entry_count {
    my( $self, $count ) = @_;
    if( $count > $self->entry_count ) {
        my $fh = $self->_filehandle;
        sysseek( $fh, $self->[RECORD_SIZE] * ($count) - 1, SEEK_SET ) && syswrite( $fh, pack( $self->[TMPL], \0 ) );
    }
} #_ensure_entry_count

=head2

Returns the number of entries in this store.
This is the same as the size of the file divided
by the record size.

=cut
sub entry_count {
    # return how many entries this index has
    my $self = shift;
    my $fh = $self->_filehandle;
    my $filesize = -s $self->[FILENAME];
    int( $filesize / $self->[RECORD_SIZE] );
}

=head2 get_record( idx )

Returns an arrayref representing the record with the given id.
The array in question is the unpacked template.

=cut
sub get_record {
    my( $self, $idx ) = @_;

    my $fh = $self->_filehandle;

    die "get record must be a positive integer" if $idx < 1;

    sysseek $fh, $self->[RECORD_SIZE] * ($idx-1), SEEK_SET or die "Could not seek ($self->[RECORD_SIZE] * ($idx-1)) : $@ $!";

    my $srv = sysread $fh, my $data, $self->[RECORD_SIZE];
    
    defined( $srv ) or die "Could not read : $@ $!";
    [unpack( $self->[TMPL], $data )];
} #get_record

=head2 next_id

adds an empty record and returns its id, starting with 1

=cut
sub next_id {
    my( $self ) = @_;
    my $fh = $self->_filehandle;
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
    truncate $self->_filehandle, ($entries-1) * $self->[RECORD_SIZE];
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
    my $next_id = 1 + $self->entry_count;
    my $fh = $self->_filehandle;
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
    my( $self, $idx, $data ) = @_;

    my $to_write = pack ( $self->[TMPL], ref $data ? @$data : $data );
    # allows the put_record to grow the data store by no more than one entry

    die "Index $idx out of bounds. Store has entry count of ".$self->entry_count if $idx > (1+$self->entry_count);

    my $fh = $self->_filehandle;

    sysseek( $fh, $self->[RECORD_SIZE] * ($idx-1), SEEK_SET ) && ( my $swv = syswrite( $fh, $to_write ) );
    1;
} #put_record

=head2 unlink_store

Removes the file for this record store entirely from the file system.

=cut
sub unlink_store {
    # TODO : more checks
    my $self = shift;
    close $self->_filehandle;
    unlink $self->[FILENAME];
}

sub _filehandle {
    my $self = shift;
    open( my $fh, "+<", $self->[FILENAME] ) or die "Unable to open ($self) $self->[FILENAME] : $!";
    $fh;
}


# ----------- end Data::RecordStore::FixedStore

1;

__END__


=head1 AUTHOR
       Eric Wolf        coyocanid@gmail.com

=head1 COPYRIGHT AND LICENSE

       Copyright (c) 2015-2017 Eric Wolf. All rights reserved.  This program is free software; you can redistribute it and/or modify it
       under the same terms as Perl itself.

=head1 VERSION
       Version 2.03  (Nov 21, 2017))

=cut
