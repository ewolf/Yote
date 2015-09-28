package DB::FixedRecordStore;




package DB::FixedStore;

use strict;

use Fcntl qw( SEEK_SET LOCK_EX LOCK_UN );
use File::Touch;
use Data::Dumper;

# SIZE --> RECORD_SIZE
sub new {
    my( $pkg, $template, $filename, $size ) = @_;
    my $class = ref( $pkg ) || $pkg;
    my $FH;
    touch $filename;
    open $FH, "+<$filename" or die "$@ $!";
    return bless { TMPL => $template, 
                   SIZE => $size || do { use bytes; length( pack( $template ) ) },
                   FILENAME => $filename,
                   FILEHANDLE => $FH,
    }, $class;
} #new

# privatize
sub filehandle {
    my $self = shift;
    close $self->{FILEHANDLE};
    open $self->{FILEHANDLE}, "+<$self->{FILENAME}";
    return $self->{FILEHANDLE};
}

sub unlink_store {
    # TODO : more checks
    my $self = shift;
    close $self->filehandle;
    unlink $self->{FILENAME};
}

sub size {
    return shift->{SIZE};
}

#
# Add a record to the end of this store. Returns the new id.
#
sub push {
    my( $self, $data ) = @_;

    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;

    my $next_id = 1 + $self->entries;
    $self->put_record( $next_id, $data );
    
#    flock $fh, LOCK_UN;

    return $next_id;
} #push

#
# Remove the last record and return it.
#
sub pop {
    my( $self ) = @_;

#    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;

    my $entries = $self->entries;
    return undef unless $entries;
    my $ret = $self->get_record( $entries );
    truncate $self->filehandle, ($entries-1) * $self->{SIZE};
    
#    flock $fh, LOCK_UN;

    return $ret;
    
} #pop

#
# The first record has id 1, not 0
#
sub put_record {
    my( $self, $idx, $data ) = @_;
    my $fh = $self->filehandle;
    sysseek $fh, $self->{SIZE} * ($idx-1), SEEK_SET or die "Could not seek : $@ $!";
    my $to_write = pack ( $self->{TMPL}, ref $data ? @$data : $data );

    my $to_write_length = do { use bytes; length( $to_write ); };
    if( $to_write_length < $self->{SIZE} ) {
        my $del = $self->{SIZE} - $to_write_length;
        $to_write .= "\0" x $del;
        my $to_write_length = do { use bytes; length( $to_write ); };
        die "$to_write_length vs $self->{SIZE}" unless $to_write_length == $self->{SIZE};
    }
    my $swv = syswrite $fh, $to_write;
    defined( $swv ) or die "Could not write : $@ $!";
    return 1;
} #put_record

sub get_record {
    my( $self, $idx ) = @_;
    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;
    sysseek $fh, $self->{SIZE} * ($idx-1), SEEK_SET or die "Could not seek ($self->{SIZE} * ($idx-1)) : $@ $!";
    my $srv = sysread $fh, my $data, $self->{SIZE};
    defined( $srv ) or die "Could not read : $@ $!";
#    flock $fh, LOCK_UN;
    return [unpack( $self->{TMPL}, $data )];
} #get_record

sub entries {
    # return how many entries this index has
    my $self = shift;
    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;
    my $filesize = -s $self->{FILENAME};
#    flock $fh, LOCK_UN;
    return int( $filesize / $self->{SIZE} );
}

#
# Empties out this file. Eeek
#
sub empty {
    my $self = shift;
    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;
    truncate $self->{FILENAME}, 0;
#    flock $fh, LOCK_UN;
    return undef;
} #empty

#
# Makes sure there at least this many entries.
#
sub ensure_entry_count {
    my( $self, $count ) = @_;
    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;

    my $entries = $self->entries;
    if( $count > $entries ) {
        for( (1+$entries)..$count ) {
            $self->put_record( $_, [] );            
        }
    } 

#    flock $fh, LOCK_UN;
} #ensure_entry_count

sub next_id {
    my( $self ) = @_;

    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;
    my $next_id = 1 + $self->entries;
    $self->put_record( $next_id, [] );
#    flock $fh, LOCK_UN;
    return $next_id;
} #next_id

package DB::FixedRecycleStore;

use strict;

use parent 'DB::FixedStore';

sub new {
    my( $pkg, $template, $filename, $size ) = @_;
    my $self = $pkg->SUPER::new( $template, $filename, $size );
    $self->{RECYCLER} = new DB::FixedStore( "L", "${filename}.recycle" );
    return bless $self, $pkg;
} #new

sub delete {
    my( $self, $idx, $purge ) = @_;
    $self->{RECYCLER}->push( $idx );
    if( $purge ) {
        $self->put_record( $idx, [] );
    }
} #delete

sub get_recycled_ids {
    my $self = shift;
    my $R = $self->{RECYCLER};
    my $max = $R->entries;
    my @ids;
    for( 1 .. $max ) {
        push @ids, @{ $R->get_record( $_ ) };
    }
    return \@ids;
} #get_recycled_ids

sub next_id {
    my $self = shift;
    my $recycled_id = $self->{RECYCLER}->pop;
    return $recycled_id ? $recycled_id->[0] : $self->SUPER::next_id;
} #next_id

package DB::StoreManager;

use strict;

use File::Path qw(make_path);

sub new {
    my( $pkg, $args ) = @_;
    my $class = ref( $pkg ) || $pkg;
    my $filename = "$args->{ store }/STORE_INDEX";
    # the store index simply stores the size of the record for that store
    return bless {
        args => $args,
        STORE_IDX => new DB::FixedStore( "I", $filename ),
        STORES    => [],
    }, $class;
} #new

sub ensure_datastore {
    my $self = shift;
    make_path( "$self->{args}{store}/stores" );
} #ensure_datastore

sub get_store {
    my( $self, $store_index, $store_size ) = @_;

    if( $self->{STORES}[ $store_index ] ) {
        return $self->{STORES}[ $store_index ];
    }
    unless( $store_size ) {
        ( $store_size ) = @{ $self->{ STORE_IDX }->get_record( $store_index ) };
    }
    my $store = new DB::FixedRecycleStore( "A*", "$self->{args}{store}/${store_index}_OBJSTORE", $store_size );
    $self->{STORES}[ $store_index ] = $store;
    return  $store;
} #get_store

sub best_store_for_size {
    my( $self, $record_size ) = @_;
    
    my( $best_idx, $best_size, $best_store ); #without going over.
    for my $idx ( 1 .. $self->{STORE_IDX}->entries ) {
        my $store = $self->get_store( $idx );
        my $store_size = $store->size;
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
    $self->{STORE_IDX}->put_record( $store_id, [$store_size] );
    my $store = $self->get_store( $store_id );

    return $store_id, $store;

} #best_store_for_size

sub get_record {
    my( $self, $store_id, $store_idx ) = @_;
    my $store = $self->get_store( $store_id );
    return $store->get_record( $store_idx );
} #get_record


1;
