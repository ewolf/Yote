package Yote::DB;

use strict;

use Yote::IO::FixedStore;
use Yote::IO::StoreManager;

use File::Path qw(make_path);
use JSON;

use constant {
    ID => 0,
    CLASS => 1,
    DATA => 2,
    RAW_DATA => 2,
    MAX_LENGTH => 1025,
};

#
# This the main index and stores in which table and position
# in that table that this object lives.
#
sub new {
    my( $pkg, $data_dir ) = @_;
    print STDERR Data::Dumper->Dump([$data_dir,"XXXOO"]);
    my $class = ref( $pkg ) || $pkg;
    make_path( $data_dir );
    my $filename = "$data_dir/OBJ_INDEX";
    # LIII template is a long ( for object id, then the table id, then the index in that table
    return bless {
        DATA_DIR      => $data_dir,
        OBJ_INDEX     => new Yote::IO::FixedRecycleStore( "LII", $filename ),
        STORE_MANAGER => new Yote::IO::StoreManager( $data_dir ),
    }, $class;
} #new

#
# Makes sure this datastore is set up and functioning.
#
sub ensure_datastore {
    my $self = shift;
    $self->{STORE_MANAGER}->ensure_datastore();
    $self->first_id;
} #ensure_datastore


#
# Return a list reference containing [ id, class, data ] that
# corresponds to the $id argument. This is used by Yote::ObjProvider
# to build the yote object.
#
sub fetch {
    my( $self, $id ) = @_;
    my $ret = $self->_fetch( $id );
    return undef unless $ret;
    $ret->[DATA] = from_json( $ret->[DATA] );
    return $ret;
} #fetch

#
# The first object in a yote data store can trace a reference to
# all active objects.
#
sub first_id {
    my $OI = shift->{OBJ_INDEX};
    if( $OI->entries < 1 ) {
        return $OI->next_id;
    }
    return 1;
} #first_id

#
# Create a new object id and return it.
#
sub get_id {
    my $self = shift;
    my $x = $self->{OBJ_INDEX}->next_id;
    return $x;
} #get_id

sub max_id {
    return shift->{OBJ_INDEX}->entries;
}

#
#
#
sub recycle_objects {
    return shift->_recycle_objects;
} #recycle_objects

sub _recycle_objects {
    my( $self, $keep_id, $store ) = @_;
    my $is_first = 0;
    unless( $keep_id ) {
        $keep_id //= $self->first_id;
        $is_first = 1;
    }
    unless( $store ) {
        # todo ... pick randomized name as this is temporary
        $store = new Yote::IO::FixedStore( "I", $self->{args}{store} . '/RECYCLE' ),
        $store->ensure_entry_count( $self->{OBJ_INDEX}->entries );
    }
    my( $has ) = @{ $store->get_record( $keep_id ) };
    return if $has;

    $store->put_record( $keep_id, [ 1 ] );
    my( @queue );
    my $item = $self->fetch( $keep_id );
    if( ref( $item->[DATA] ) eq 'ARRAY' ) {
        ( @queue ) = grep { /^[^v]/ } @{$item->[DATA]};
    } else {
        ( @queue ) = grep { /^[^v]/ } values %{$item->[DATA]};
    }
    for my $keeper ( @queue ) {
        $self->_recycle_objects( $keeper, $store );
    }
    if( $is_first ) {
        # the purge begins here
        my $count = 0;
        my $cands = $store->entries;
        for( 1..$cands) {
            my( $rec ) = @{ $store->get_record( $_ ) };
            if( ! $rec ) {
                ++$count;
                my $o = $self->fetch( $_ );
            }
        }
        # remove recycle datastore
        $store->unlink;

        return $count;
    }
} #recycle_objects

#
# Saves the object data for object $id to the data store.
#
sub stow {
    my( $self, $id, $class, $data ) = @_;
    my $save_data = "$class " . to_json($data);
    my $save_size = do { use bytes; length( $save_data ); };
    my( $current_store_id, $current_store_idx ) = @{ $self->{OBJ_INDEX}->get_record( $id ) };

    # check to see if this is already in a store and record that store.
    if( $current_store_id ) {
        my $old_store = $self->{STORE_MANAGER}->get_store( $current_store_id );
        if( $old_store->{SIZE} >= $save_size ) {
            $old_store->put_record( $current_store_idx, [$save_data] );
            return;
        }
        $old_store->delete( $current_store_idx );
    }

    # find a store large enough and store it there.
    my( $store_id, $store ) = $self->{STORE_MANAGER}->best_store_for_size( $save_size );
    my $store_idx = $store->next_id;

# okey, looks like the providing the next index is not working well with the recycling. is providing the same one?
    $self->{OBJ_INDEX}->put_record( $id, [ $store_id, $store_idx ] );

    my $ret = $store->put_record( $store_idx, [$save_data] );

    return $ret;
} #stow

# -------------------- private

#
# Returns [ id, class, raw data ] of the record associated with that object id.
# The raw data is a JSON string, not an object reference.
#
sub _fetch {
    my( $self, $id ) = @_;

    my( $store_id, $store_idx ) = @{ $self->{OBJ_INDEX}->get_record( $id ) };

    return undef unless $store_id;

    my( $data ) = @{ $self->{STORE_MANAGER}->get_record( $store_id, $store_idx ) };

    my $pos = index( $data, ' ' );
    die "Malformed record '$data'" if $pos == -1;
    my $class = substr $data, 0, $pos;
    my $val   = substr $data, $pos + 1;

    return [$id,$class,$val];
} #_fetch


sub hash_delete {
    my( $self, $hash_id, $key ) = @_;
    my $obj = $self->fetch( $hash_id );
    die "hash_delete called for array" if ref( $obj->[DATA] ) eq 'ARRAY';
    delete $obj->[DATA]{ $key };
    return $self->stow( @$obj );
} #hash_delete


sub hash_insert {
    my( $self, $hash_id, $key, $val ) = @_;
    my $obj = $self->fetch( $hash_id );
    die "hash_insert called for array" if ref( $obj->[DATA] ) eq 'ARRAY';
    $obj->[DATA]{ $key } = $val;
    return $self->stow( @$obj );
} #hash_insert

#
# Delete the first occurance of val or the thing at the given index.
#
sub list_delete {
    my( $self, $list_id, $val, $idx ) = @_;
    my $obj = $self->fetch( $list_id );
    die "list_delete called for non array" if ref( $obj->[DATA] ) ne 'ARRAY';
    my $list = $obj->[DATA];
    my $actual_index = $idx;
    if( $val ) {
        ( $actual_index ) = grep { $list->[$_] eq $val  } (0..$#$list);
    }
    splice @$list, $actual_index, 1;
    return $self->stow( @$obj );
} #list_delete

sub list_fetch {
    my( $self, $list_id, $idx ) = @_;
    my $obj = $self->fetch( $list_id );
    die "list_fetch called for non array" if ref( $obj->[DATA] ) ne 'ARRAY';
    return $obj->[DATA][$idx];
} #list_fetch

sub hash_fetch {
    my( $self, $hash_id, $key ) = @_;
    my $obj = $self->fetch( $hash_id );
    return $obj->[DATA][$key] if ref( $obj->[DATA] ) eq 'ARRAY';
    return $obj->[DATA]{$key};
} #hash_fetch

sub hash_has_key {
    my( $self, $hash_id, $key ) = @_;
    my $obj = $self->fetch( $hash_id );
    die "hash_has_key called for array" if ref( $obj->[DATA] ) eq 'ARRAY';
    return defined $obj->[DATA]{$key};
} #hash_has_key


1;

__END__
