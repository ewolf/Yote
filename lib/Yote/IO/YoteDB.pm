package Yote::IO::YoteDB;

use strict;

use Yote::IO::FixedStore;
use Yote::IO::StoreManager;

use File::Path qw(make_path);

#
# This the main index and stores in which table and position 
# in that table that this object lives.
#
sub new {
    my( $pkg, $args ) = @_;
    my $class = ref( $pkg ) || $pkg;
    make_path( $args->{ store } );
    my $filename = "$args->{ store }/OBJ_INDEX";
    # LII template is a long ( for object id, then the table id, then the index in that table
    return bless {
        args          => $args,
        OBJ_INDEX     => new Yote::IO::FixedStore( "LII", $filename ),
        STORE_MANAGER => new Yote::IO::StoreManager( $args ),
    }, $class;
} #new

sub fetch {
    my( $self, $id ) = @_;

    my( $store_id, $store_idx ) = @{ $self->{OBJ_INDEX}->get_record( $id ) };
    return $self->{STORE_MANAGER}->get_record( $store_id, $store_idx );

} #fetch

sub stow {
    my( $self, $id, $class, $data ) = @_;

    my $save_data = "$class $data";
    my $save_size = do { use bytes; length( $save_data ); };

    my( $current_store_id, $current_store_idx ) = @{ $self->{OBJ_INDEX}->get_record( $id ) };
    # check to see if this is already in a table and 
    # it still fits in that table
    if( $current_store_id ) {
        my $store = $self->{STORE_MANAGER}->get_store( $current_store_id );
        if( $store->size() <= $save_size ) {
            return $store->put_record( $current_store_idx, [$save_data] );
        } 
        # otherwise delete the current record in that store
        $store->delete( $current_store_id );
    }
    
    # find a store large enough and store it there.
    my( $store_id, $store ) = $self->{STORE_MANAGER}->best_store_for_size( $save_size );
    my $store_idx = $store->next_id;
    $self->{OBJ_INDEX}->put_record( $id, [ $store_id, $store_idx ] );
    $store->put_record( $store_idx, [$save_data] );
    
} #stow

sub ensure_datastore {
    my $self = shift;
    $self->{STORE_MANAGER}->ensure_datastore();
} #ensure_datastore

sub first_id {
    return 1;
}

sub get_id {
    my( $self, $class ) = @_;
    return $self->{OBJ_INDEX}->next_id;
}

1;

__END__
