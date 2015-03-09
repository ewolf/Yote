package Yote::IO::StoreManager;

use strict;

use Yote::IO::FixedStore;
use Yote::IO::FixedRecycleStore;

sub new {
    my( $pkg, $args ) = @_;
    my $class = ref( $pkg ) || $pkg;
    my $filename = "$args->{ store }/STORE_INDEX";
    # the store index simply stores the size of the record for that store
    return bless {
        args => $args,
        STORE_IDX => new Yote::IO::FixedStore( "I", $filename ),
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
    my $store = new Yote::IO::FixedRecycleStore( "A*", "$self->{args}{store}/${store_index}_OBJSTORE", $store_size );
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

__END__
