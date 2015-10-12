package DB::DataStore;

=head1 NAME

DB::DataStore - Simple and fast record based data store

=head1 SYNPOSIS

use DB::DataStore;


my $store = DB::DataStore->open( $directory );

my $data = "TEXT DATA OR BYTES";
my $id    = $store->stow( $data, $optionalID );

my $val   = $store->fetch( $id );

$store->recycle( $id );

my $new_id = $store->next_id; # $new_id == $id

$store->stow( "MORE DATA", $new_id );

=head1 DESCRIPTION

A simple and fast way to store arbitrary text or byte data.
It is written entirely in perl with no non-core dependencies. It is designed to be
both easy to set up and easy to use.

=head1 LIMITATIONS

DB::DataStore is not meant to store huge amounts of data. 
It will fail if it tries to create a file size greater than the 
max allowed by the filesystem. This limitation will be removed in 
subsequent versions. This limitation is most important when working
with sets of data that approach the max file size of the system 
in question.

This is not written with thread safety in mind, so unexpected behavior
can occur when multiple DB::DataStore objects open the same directory.

=cut

use strict;
use warnings;

use File::Path qw(make_path);
use Data::Dumper;

use vars qw($VERSION);

$VERSION = '1.04';

=head1 METHODS

=head2 open( directory )

Takes a single argument - a directory, and constructs the data store in it. 
The directory must be writeable or creatible. If a DataStore already exists
there, it opens it, otherwise it creates a new one.

=cut
sub open {
    my( $pkg, $directory ) = @_;

    make_path( "$directory/stores", { error => \my $err } );
    if( @$err ) {
        my( $err ) = values %{ $err->[0] };
        die $err;
    }
    my $filename = "$directory/STORE_INDEX";

    bless {
        DIRECTORY => $directory,
        OBJ_INDEX => DB::DataStore::FixedRecycleStore->open( "IL", "$directory/OBJ_INDEX" ),
        STORE_IDX => DB::DataStore::FixedStore->open( "I", $filename ),
        STORES    => [],
    }, ref( $pkg ) || $pkg;
    
} #open

=head2 entry_count

Returns how many entries are in this store. Recycling ids does
_not_ decrement this entry_count.

=cut
sub entry_count {
    shift->{OBJ_INDEX}->entry_count;
}

=head2 ensure_entry_count( min_count )

This makes sure there there are at least min_count
entries in this datastore. This creates empty
records if needed.

=cut
sub ensure_entry_count {
    shift->{OBJ_INDEX}->ensure_entry_count( shift );
}

=head2 next_id

This sets up a new empty record and returns the 
id for it.

=cut
sub next_id {
    my $self = shift;
    $self->{OBJ_INDEX}->next_id;
}

=head2 stow( data, optionalID )

This saves the text or byte data to the datastore.
If an id is passed in, this saves the data to the record
for that id, overwriting what was there. 
If an id is not passed in, it creates a new datastore.

Returns the id of the record written to.

=cut
sub stow {
    my( $self, $data, $id ) = @_;
    $id //= $self->{OBJ_INDEX}->next_id;

    my $save_size = do { use bytes; length( $data ); };

    my( $current_store_id, $current_idx_in_store ) = @{ $self->{OBJ_INDEX}->get_record( $id ) };

    #
    # Check if this record had been saved before, and that the
    # store is was in has a large enough record size.
    #
    if( $current_store_id ) {
        my $old_store = $self->_get_store( $current_store_id );

        warn "object '$id' references store '$current_store_id' which does not exist" unless $old_store;

        if( $old_store->{RECORD_SIZE} >= $save_size ) {
            $old_store->put_record( $current_idx_in_store, [$data] );
            return $id;
        }
        
        # the old store was not big enough (or missing), so remove its record from 
        # there.
        $old_store->recycle( $current_idx_in_store, 1 ) if $old_store;
    }

    my( $store_id, $store ) = $self->_best_store_for_size( $save_size );
    my $index_in_store = $store->next_id;

    $self->{OBJ_INDEX}->put_record( $id, [ $store_id, $index_in_store ] );
    $store->put_record( $index_in_store, [ $data ] );

    $id;
} #stow

=head2 fetch( id )

Returns the record associated with the ID. If the ID has no 
record associated with it, undef is returned.

=cut
sub fetch {
    my( $self, $id ) = @_;
    my( $store_id, $id_in_store ) = @{ $self->{OBJ_INDEX}->get_record( $id ) };
    return undef unless $store_id;

    my $store = $self->_get_store( $store_id );
    my( $data ) = @{ $store->get_record( $id_in_store ) };
    $data;
} #fetch

=head2 recycle( $id )

This marks that the record associated with the id may be reused.
Calling this does not decrement the number of entries reported 
by the datastore.

=cut
sub recycle {
    my( $self, $id ) = @_;
    my( $store_id, $id_in_store ) = @{ $self->{OBJ_INDEX}->get_record( $id ) };
    return undef unless defined $store_id;
    
    my $store = $self->_get_store( $store_id );
    $store->recycle( $id_in_store );
    $self->{OBJ_INDEX}->recycle( $id_in_store );

} #recycle

sub _best_store_for_size {
    my( $self, $record_size ) = @_;
    my( $best_idx, $best_size, $best_store ); #without going over.

    # using the written record rather than the array of stores to 
    # determine how many there are.
    for my $idx ( 1 .. $self->{STORE_IDX}->entry_count ) {
        my $store = $self->_get_store( $idx );
        my $store_size = $store->{RECORD_SIZE};
        if( $store_size >= $record_size ) {
            if( ! defined( $best_size ) || $store_size < $best_size ) {
                $best_idx   = $idx;
                $best_size  = $store_size;
                $best_store = $store;
            }
        }
    } #each store
    
    if( $best_store ) {
        return $best_idx, $best_store;
    } 

    # Have to create a new store. 
    # Make one that is thrice the size of the record
    my $store_size = 3 * $record_size;
    my $store_id = $self->{STORE_IDX}->next_id;

    # first, make an entry in the store index, giving it that size, then
    # fetch it?
    $self->{STORE_IDX}->put_record( $store_id, [$store_size] );

    my $store = $self->_get_store( $store_id );

    $store_id, $store;

} #_best_store_for_size

sub _get_recycled_ids {
    shift->{OBJ_INDEX}->get_recycled_ids;
}

sub _get_store {
    my( $self, $store_index ) = @_;

    if( $self->{STORES}[ $store_index ] ) {
        return $self->{STORES}[ $store_index ];
    }

    my( $store_size ) = @{ $self->{ STORE_IDX }->get_record( $store_index ) };

    # since we are not using a pack template with a definite size, the size comes from the record

    my $store = DB::DataStore::FixedRecycleStore->open( "A*", "$self->{DIRECTORY}/${store_index}_OBJSTORE", $store_size );
    $self->{STORES}[ $store_index ] = $store;
    $store;
} #_get_store

# ----------- end DB::DataStore
=head1 HELPER PACKAGES

DB::DataStore relies on two helper packages that are useful in 
their own right and are documented here.

=head1 HELPER PACKAGE

DB::DataStore::FixedStore

=head1 DESCRIPTION

A fixed record store that uses perl pack and unpack templates to store
identically sized sets of data and uses a single file to do so.

=head1 SYNOPSIS

my $template = "LII"; # perl pack template. See perl pack/unpack.

my $size;   #required if the template does not have a definite size, like A*

my $store = DB::DataStore::FixedStore->open( $template, $filename, $size );

my $new_id = $store->next_id;

$store->put_record( $id, [ 321421424243, 12, 345 ] );

my $more_data = $store->get_record( $other_id );

my $removed_last = $store->pop;

my $last_id = $store->push( $data_at_the_end );

my $entries = $store->entry_count;

if( $entries < $min ) {

    $store->ensure_entry_count( $min );

}

$store->emtpy;

$store->unlink_store;

=head1 METHODS

=cut
package DB::DataStore::FixedStore;

use strict;
use warnings;

use Fcntl qw( SEEK_SET LOCK_EX LOCK_UN );

=head2 open( template, filename, size )

Opens or creates the file given as a fixed record 
length data store. If a size is not given,
it calculates the size from the template, if it can.
This will die if a zero byte record size is determined.

=cut
sub open {
    my( $pkg, $template, $filename, $size ) = @_;
    my $class = ref( $pkg ) || $pkg;
    my $FH;
    my $useSize = $size || do { use bytes; length( pack( $template ) ) };
    die "Cannot open a zero record sized fixed store" unless $useSize;
    unless( -e $filename ) {
        CORE::open $FH, ">$filename";
        print $FH "";
        close $FH;
    }
    CORE::open $FH, "+<$filename" or die "$@ $!";
    bless { TMPL => $template, 
            RECORD_SIZE => $useSize,
            FILENAME => $filename,
            FILEHANDLE => $FH,
    }, $class;
} #open

=head2 empty

This empties out the database, setting it to zero records.

=cut
sub empty {
    my $self = shift;
    my $fh = $self->_filehandle;
    truncate $self->{FILENAME}, 0;
    undef;
} #empty

=head2 ensure_entry_count( count )

Makes sure the data store has at least as many entries
as the count given. This creates empty records if needed 
to rearch the target record count.

=cut
sub ensure_entry_count {
    my( $self, $count ) = @_;
    my $fh = $self->_filehandle;

    my $entries = $self->entry_count;
    if( $count > $entries ) {
        for( (1+$entries)..$count ) {
            $self->put_record( $_, [] );
        }
    } 
} #ensure_entry_count

=head2

Returns the number of entries in this store.
This is the same as the size of the file divided
by the record size.

=cut
sub entry_count {
    # return how many entries this index has
    my $self = shift;
    my $fh = $self->_filehandle;
    my $filesize = -s $self->{FILENAME};
    int( $filesize / $self->{RECORD_SIZE} );
}

=head2 get_record( idx )

Returns an arrayref representing the record with the given id.
The array in question is the unpacked template.

=cut
sub get_record {
    my( $self, $idx ) = @_;

    my $fh = $self->_filehandle;

# how about an ensure_entry_count right here?
# also a has_record
    unless( $idx > 0 ) {
        print STDERR Data::Dumper->Dump(["HI"]);
        use Carp 'longmess'; 
        print STDERR Data::Dumper->Dump([longmess]); }
    sysseek $fh, $self->{RECORD_SIZE} * ($idx-1), SEEK_SET or die "Could not seek ($self->{RECORD_SIZE} * ($idx-1)) : $@ $!";
    my $srv = sysread $fh, my $data, $self->{RECORD_SIZE};
    defined( $srv ) or die "Could not read : $@ $!";
    [unpack( $self->{TMPL}, $data )];
} #get_record

=head2 next_id

adds an empty record and returns its id, starting with 1

=cut
sub next_id {
    my( $self ) = @_;
    my $fh = $self->_filehandle;
    my $next_id = 1 + $self->entry_count;
    $self->put_record( $next_id, [] );
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
    truncate $self->_filehandle, ($entries-1) * $self->{RECORD_SIZE};
    $ret;
} #pop

=head2 push( data )

Add a record to the end of this store. Returns the id assigned
to that record. The data must be a scalar or list reference.
If a list reference, it should conform to the pack template
assigned to this store.

=cut
sub push {
    my( $self, $data ) = @_;
    my $fh = $self->_filehandle;
    my $next_id = 1 + $self->entry_count;
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
    my $fh = $self->_filehandle;
    my $to_write = pack ( $self->{TMPL}, ref $data ? @$data : $data );

    my $to_write_length = do { use bytes; length( $to_write ); };
    if( $to_write_length < $self->{RECORD_SIZE} ) {
        my $del = $self->{RECORD_SIZE} - $to_write_length;
        $to_write .= "\0" x $del;
        my $to_write_length = do { use bytes; length( $to_write ); };
        die "$to_write_length vs $self->{RECORD_SIZE}" unless $to_write_length == $self->{RECORD_SIZE};
    }

# how about an ensure_entry_count right here?

    sysseek( $fh, $self->{RECORD_SIZE} * ($idx-1), SEEK_SET ) && ( my $swv = syswrite( $fh, $to_write ) );
    defined( $swv ) or die "Could not write : $@ $!";
    1;
} #put_record

=head2 unlink_store

Removes the file for this record store entirely from the file system.

=cut
sub unlink_store {
    # TODO : more checks
    my $self = shift;
    close $self->_filehandle;
    unlink $self->{FILENAME};
}

sub _filehandle {
    my $self = shift;
    close $self->{FILEHANDLE};
    CORE::open( $self->{FILEHANDLE}, "+<$self->{FILENAME}" );
    $self->{FILEHANDLE};
}


# ----------- end DB::DataStore::FixedStore



=head1 HELPER PACKAGE

DB::DataStore::FixedRecycleStore

=head1 SYNOPSIS

A subclass DB::DataStore::FixedRecycleStore. This allows
indexes to be recycled and their record space reclaimed.

my $store = DB::DataStore::FixedRecycleStore->open( $template, $filename, $size );

my $id = $store->next_id;

$store->put_record( $id, ["SOMEDATA","FOR","PACK" ] );

my $id2 = $store->next_id; # == 2 

$store->recycle( $id );

my $avail_ids = $store->get_recycled_ids; # [ 1 ]

my $id3 = $store->next_id;

$id3 == $id;

=cut
package DB::DataStore::FixedRecycleStore;

use strict;
use warnings;

our @ISA='DB::DataStore::FixedStore';

sub open {
    my( $pkg, $template, $filename, $size ) = @_;
    my $self = DB::DataStore::FixedStore->open( $template, $filename, $size );
    $self->{RECYCLER} = DB::DataStore::FixedStore->open( "L", "${filename}.recycle" );
    bless $self, $pkg;
} #open

=head1 METHODS

=head2 recycle( $idx )

Recycles the given id and reclaims its space.

=cut
sub recycle {
    my( $self, $idx ) = @_;
    $self->{RECYCLER}->push( [$idx] );
} #recycle

=head2 get_recycled_ids

Returns a list reference of ids that are available
to be reused.

=cut
sub get_recycled_ids {
    my $self = shift;
    my $R = $self->{RECYCLER};
    my $max = $R->entry_count;
    my @ids;
    for( 1 .. $max ) {
        push @ids, @{ $R->get_record( $_ ) };
    }
    \@ids;
} #get_recycled_ids

sub next_id {
    my $self = shift;

    my( $recycled_id ) = @{ $self->{RECYCLER}->pop || []};
    $recycled_id = $recycled_id ? $recycled_id : $self->SUPER::next_id;
} #next_id

# ----------- end package DB::DataStore::FixedRecycleStore;

1;

__END__


=head1 AUTHOR
       Eric Wolf        coyocanid@gmail.com

=head1 COPYRIGHT AND LICENSE

       Copyright (c) 2015 Eric Wolf. All rights reserved.  This program is free software; you can redistribute it and/or modify it
       under the same terms as Perl itself.

=head1 VERSION
       Version 1.04  (October 12, 2015))

=cut
