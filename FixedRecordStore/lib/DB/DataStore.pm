package DB::DataStore;

=head1 NAME

DB::DataStore

=head1 SYNPOSIS

use DB::DataStore;

my $store = DB::DataStore::open( $directory );
my $id    = $store->stow( $data, $optionalID );
my $val   = $store->fetch( $id );

$store->recycle( $id );

=cut

use strict;
use File::Path qw(make_path);
use Data::Dumper;

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

sub entry_count {
    shift->{OBJ_INDEX}->entry_count;
}

sub ensure_entry_count {
    shift->{OBJ_INDEX}->ensure_entry_count( shift );
}

sub next_id {
    my $self = shift;
    $self->{OBJ_INDEX}->next_id;
}

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
            return;
        }
        
        # the old store was not big enough (or missing), so remove its record from 
        # there.
        $old_store->recycle( $current_idx_in_store, 1 ) if $old_store;
    }

    my( $store_id, $store ) = $self->_best_store_for_size( $save_size );
    my $index_in_store = $store->next_id;

    $self->{OBJ_INDEX}->put_record( $id, [ $store_id, $index_in_store ] );
    $store->put_record( $index_in_store, [ $data ] );
    
} #stow

sub fetch {
    my( $self, $id ) = @_;
    my( $store_id, $id_in_store ) = @{ $self->{OBJ_INDEX}->get_record( $id ) };
    return undef unless $store_id;

    my $store = $self->_get_store( $store_id );
    my( $data ) = @{ $store->get_record( $id_in_store ) };
    $data;
} #fetch

sub recycle {
    my( $self, $id, $clear ) = @_;
    my( $store_id, $id_in_store ) = @{ $self->{OBJ_INDEX}->get_record( $id ) };
    return undef unless defined $store_id;
    
    my $store = $self->_get_store( $store_id, $clear );
    $store->recycle( $id_in_store );

} #recycle

sub _best_store_for_size {
    my( $self, $record_size ) = @_;
    my( $best_idx, $best_size, $best_store ); #without going over.

    # using the written record rather than the array of stores to 
    # determine how many there are.
    for my $idx ( 1 .. $self->{STORE_IDX}->entry_count ) {
        my $store = $self->_get_store( $idx );
        my $store_size = $store->record_size;
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

    return $store_id, $store;

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
    return $store;
} #_get_store

# ----------- end package DB::DataStore

=head1 NAME

DB::DataStore::FixedStore

=head1 SYNOPSIS

my $template = "LII"; # perl pack template. See perl pack/unpack.
my $size;   #required if the template does not have a definite size, like A*
my $store = DB::DataStore::FixedStore::open( $template, $filename, $size );

my $new_id = $store->next_id;
$store->put_record( $new_id, $data );

my $more_data = $store->get_record( $other_id );
my $last_data = $store->pop;
$store->push( $new_last_data );

my $rsize = $store->record_size;

my $entries = $store->entry_count;

if( $entries < $min ) {
    $store->ensure_empty_count( $min );
}

$store->emtpy;
$store->unlink_store;

=head1 DESCRIPTION

=cut
package DB::DataStore::FixedStore;

use Fcntl qw( SEEK_SET LOCK_EX LOCK_UN );
use File::Touch;

sub open {
    my( $pkg, $template, $filename, $size ) = @_;
    my $class = ref( $pkg ) || $pkg;
    my $FH;
    touch $filename;
    open $FH, "+<$filename" or die "$@ $!";
    return bless { TMPL => $template, 
                   RECORD_SIZE => $size || do { use bytes; length( pack( $template ) ) },
                   FILENAME => $filename,
                   FILEHANDLE => $FH,
    }, $class;
} #open

#
# Empties out this file. Eeek
#
sub empty {
    my $self = shift;
    my $fh = $self->_filehandle;
    truncate $self->{FILENAME}, 0;
    return undef;
} #empty

#
# Makes sure there at least this many entries, even if some are blank.
# Used by recycling.
#
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

sub entry_count {
    # return how many entries this index has
    my $self = shift;
    my $fh = $self->_filehandle;
    my $filesize = -s $self->{FILENAME};
    return int( $filesize / $self->{RECORD_SIZE} );
}

sub get_record {
    my( $self, $idx ) = @_;
    my $fh = $self->_filehandle;
    sysseek $fh, $self->{RECORD_SIZE} * ($idx-1), SEEK_SET or die "Could not seek ($self->{RECORD_SIZE} * ($idx-1)) : $@ $!";
    my $srv = sysread $fh, my $data, $self->{RECORD_SIZE};
    defined( $srv ) or die "Could not read : $@ $!";
    return [unpack( $self->{TMPL}, $data )];
} #get_record


# adds an empty record and returns its id, starting with 1
sub next_id {
    my( $self ) = @_;

    my $fh = $self->_filehandle;
    my $next_id = 1 + $self->entry_count;
    $self->put_record( $next_id, [] );
    return $next_id;
} #next_id


#
# Remove the last record and return it. This is used by the recycling subclass.
#
sub pop {
    my( $self ) = @_;

    my $entries = $self->entry_count;
    return undef unless $entries;
    my $ret = $self->get_record( $entries );
    truncate $self->_filehandle, ($entries-1) * $self->{RECORD_SIZE};

    $ret;
} #pop

#
# Add a record to the end of this store. Returns the new id.
#
sub push {
    my( $self, $data ) = @_;
    my $fh = $self->_filehandle;
    my $next_id = 1 + $self->entry_count;
    $self->put_record( $next_id, [$data] );
    return $next_id;
} #push

#
# The first record has id 1, not 0
#
sub put_record {
    my( $self, $idx, $data ) = @_;
    my $fh = $self->_filehandle;
    sysseek $fh, $self->{RECORD_SIZE} * ($idx-1), SEEK_SET or die "Could not seek : $@ $!";
    my $to_write = pack ( $self->{TMPL}, ref $data ? @$data : $data );

    my $to_write_length = do { use bytes; length( $to_write ); };
    if( $to_write_length < $self->{RECORD_SIZE} ) {
        my $del = $self->{RECORD_SIZE} - $to_write_length;
        $to_write .= "\0" x $del;
        my $to_write_length = do { use bytes; length( $to_write ); };
        die "$to_write_length vs $self->{RECORD_SIZE}" unless $to_write_length == $self->{RECORD_SIZE};
    }
    my $swv = syswrite $fh, $to_write;
    defined( $swv ) or die "Could not write : $@ $!";
    return 1;
} #put_record


sub record_size {
    return shift->{RECORD_SIZE};
}

sub unlink_store {
    # TODO : more checks
    my $self = shift;
    close $self->_filehandle;
    unlink $self->{FILENAME};
}


# privatize
sub _filehandle {
    my $self = shift;
    close $self->{FILEHANDLE};
    open $self->{FILEHANDLE}, "+<$self->{FILENAME}";
    return $self->{FILEHANDLE};
}


# ----------- end package DB::DataStore::FixedStore
=head1 NAME

DB::DataStore::FixedRecycleStore

=head1 SYNOPSIS

Same as DB::DataStore::FixedRecycleStore plus

$store->recycle( $entry_id );

$store->get_recycled_ids;

=cut
package DB::DataStore::FixedRecycleStore;

our @ISA='DB::DataStore::FixedStore';
sub open {
    my( $pkg, $template, $filename, $size ) = @_;
    my $self = DB::DataStore::FixedStore->open( $template, $filename, $size );
    $self->{RECYCLER} = DB::DataStore::FixedStore->open( "L", "${filename}.recycle" );
    return bless $self, $pkg;
} #open

sub recycle {
    my( $self, $idx, $purge ) = @_;
    $self->{RECYCLER}->push( $idx );
    if( $purge  ) {
        $self->put_record( $idx, [] );
    }
} #recycle

sub get_recycled_ids {
    my $self = shift;
    my $R = $self->{RECYCLER};
    my $max = $R->entry_count;
    my @ids;
    for( 1 .. $max ) {
        push @ids, @{ $R->get_record( $_ ) };
    }
    return \@ids;
} #get_recycled_ids

sub next_id {
    my $self = shift;
    my $recycled_id = @{ $self->{RECYCLER}->pop || []};
    return $recycled_id ? $recycled_id->[0] : $self->SUPER::next_id;
} #next_id

# ----------- end package DB::DataStore::FixedRecycleStore;

1;

__END__
