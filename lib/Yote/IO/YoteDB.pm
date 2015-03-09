package Yote::IO::YoteDB;

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
    my( $pkg, $args ) = @_;
    my $class = ref( $pkg ) || $pkg;
    make_path( $args->{ store } );
    my $filename = "$args->{ store }/OBJ_INDEX";
    # LIII template is a long ( for object id, then the table id, then the index in that table
    return bless {
        args          => $args,
        OBJ_INDEX     => new Yote::IO::FixedStore( "LII", $filename ),
        STORE_MANAGER => new Yote::IO::StoreManager( $args ),
    }, $class;
} #new

# ------------------------------------------------

#
# Dummy stub. Does nothing as this datastore
# automatically commits transactions
#
sub commit_transaction {}

#
# Given a host object id and a container name,
# this returns the reference type of what
# is in that container.
# for example :
#   my $obj = new Yote::Obj;
#   $obj->set_foo( [ 'My', "List", "Of", "Stuff" ] );
#   $obj->container_type( 'foo' ); <--- returns 'ARRAY'
#   
#
sub container_type {
    my( $self, $host_id, $container_name ) = @_;
    my $obj = $self->fetch( $host_id );
    if( $obj ) {
        my $container = $obj->[CLASS] eq 'ARRAY' ? 
            $self->fetch( $obj->[DATA][$container_name] ) :
            $self->fetch( $obj->[DATA]{$container_name} );
        if( $container ) {
            return $obj->[CLASS];
        }
    }
    return undef;
} #container_type

#
# Returns the count of objects attached to the 
# host obj_id that match the criteria.
# arguments are 
#    search_terms   - a list of terms to match
#    search_fields  - if given, must be same size as search_terms
#                     searches each field in this list with the matching
#                     term from the search_terms at the same index.
#                     if present, hashkey_search is ignored.
#    hashkey_search - if true, this only searches the object property
#                     names. 
#
sub count {
    my( $self, $obj_id, $args ) = @_;

    my $obj = $self->fetch( $obj_id );
    if( $obj ) {
        my $odata  = $obj->[DATA];
        my $terms  = $args->{ search_terms } || [];
        my $fields = $args->{ search_fields } || [];
        my $hashkey_search = $args->{ hashkey_search };
        return scalar(
            grep { $self->_matches( $_, $terms, $fields, $hashkey_search ) }
            map { $self->_fetch($_) } 
            grep { ! /^v/ } 
            ($obj->[CLASS] eq 'ARRAY' ? @$odata : values %$odata)
            );
    }
    return 0;
} #count

#
# Dummy stub. Does nothing.
#
sub disconnect {}

#
# Makes sure this datastore is set up and functioning.
#
sub ensure_datastore {
    my $self = shift;
    $self->{STORE_MANAGER}->ensure_datastore();
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
    return 1;
} #first_id

#
# Create a new object id and return it.
#
sub get_id {
    return shift->{OBJ_INDEX}->next_id;
} #get_id


#
# Add the value or id to the list, at an optional index.
# Will die if the list_id does not point to a list.
#
sub list_insert {
    my( $self, $list_id, $val, $idx ) = @_;
    my $obj = $self->fetch( $list_id );
    die "list insert called for non-list" unless ref( $obj->{DATA} ) eq 'ARRAY';
    if( defined $idx ) {
        splice @{$obj->{DATA}}, $idx, 0, $val;
    } else {
        push @{$obj->{DATA}}, $val;
    }
    $self->stow( @$obj );
    return;
} #list_insert

sub max_id {
    return shift->{OBJ_INDEX}->size;
}

#
# Returns a paginated list of objects attached to the 
# host obj_id that match the criteria.
# arguments are 
#    limit           - return no more than this amount
#    skip            - skip this many entries to paginate
#    search_terms    - a list of terms to match
#    search_fields   - if given, must be same size as search_terms
#                      searches each field in this list with the matching
#                      term from the search_terms at the same index.
#                      if present, hashkey_search is ignored.
#    hashkey_search -  search on the field names rather than the fields.
#                      Makes no sense if search_fields is given.
#    reverse         - reverse the return array
#    sort_fields     - the fields to sort these on
#    reversed_orders - a list of booleans corresponding to sort_fields. 
#                      If the second reversed_orders entry is true, then
#                      the 2nd field to sort on will be sorted in reverse.
#    numeric_fields  - a list of booleans corresponding to sort_fields. 
#                      If the second numeric_fields entry is true, then
#                      the 2nd field to sort on will be sorted numerically
#                      rather than as strings which is the default.
#
sub paginate {
    my( $self, $obj_id, $args ) = @_;

    my $idx = 0;
    
    my $obj = $self->fetch( $obj_id );
    if( $obj ) {
        my $odata = $obj->[DATA];
        my $search_terms  = $args->{ search_terms } || [];
        my $search_fields = $args->{ search_fields } || [];
        my $sort_fields   = $args->{ sort_fields } || [];
        my( $hashkey_search, $skip, $limit ) = @$args{ 'hashkey_search', 'skip', 'limit' };


        my( @cand_ids ) = grep { index($_,'v') != 0 } ($obj->[CLASS] eq 'ARRAY' ? @$odata : values %$odata);
        if( $args->{reverse} && @$sort_fields == 0 ) {
            (@cand_ids) = reverse @cand_ids;
        }

        my( @accepted_cand_data, $tries );
        for my $cand_id (@cand_ids) {
            my $cand_data = $self->_fetch( $cand_id );
            next unless $self->_matches( $cand_data, $search_terms, $search_fields, $hashkey_search );
            ++$tries;
            if( @$sort_fields == 0 ) {
                if( defined( $limit ) ) {
                    next if $skip >= $tries;
                    push @accepted_cand_data, $cand_data->[ID];
                    if( @accepted_cand_data >= $limit ) {
                        return \@accepted_cand_data;
                    }
                } else {
                    push @accepted_cand_data, $cand_data->[ID];
                }
            } elsif( $cand_data ) {
                push @accepted_cand_data, $cand_data;
            }
        } #each cand
        if( @$sort_fields == 0 ) {
            print STDERR Data::Dumper->Dump([\@accepted_cand_data]);
            return [map { $_->[ID] } @accepted_cand_data];
        }

        my( @converted_arrays );
        for my $cand (@accepted_cand_data) {
            my $data = from_json( $cand->[DATA] );
            if( $cand->[DATA] eq 'ARRAY' ) {
                # temporarily convert arrays to hashes for comparison.
                # later convert them back
                push @converted_arrays, $cand;
                $data = { map { $_ => $data->[$_] } (0..$#$data) };
            }
            $cand->[DATA] = $data;
        }

        my $reversed_orders = $args->{ reversed_orders } || [];
        my $numeric_fields = $args->{ numeric_fields } || [];
        for my $fld_idx ( 0..$#$sort_fields ) {
            my $fld = $sort_fields->[ $fld_idx ];
            if( $reversed_orders->[ $fld_idx ] ) {
                if( $numeric_fields->[ $fld_idx ] ) {
                    @accepted_cand_data = sort {
                        $b->[DATA]{$fld} <=> $a->[DATA]{$fld}
                    } @accepted_cand_data;
                } else {
                    @accepted_cand_data = sort {
                        $b->[DATA]{$fld} cmp $a->[DATA]{$fld}
                    } @accepted_cand_data;
                }
            } elsif( $numeric_fields->[ $fld_idx ] ) {
                @accepted_cand_data = sort {
                    $a->[DATA]{$fld} <=> $b->[DATA]{$fld}
                } @accepted_cand_data;
            } else {
                @accepted_cand_data = sort {
                    $a->[DATA]{$fld} cmp $b->[DATA]{$fld}
                } @accepted_cand_data;
            }
        }
        
        #convert back array candidate data from hash back to array
        for my $arr_cand (@converted_arrays) {
             $arr_cand->[DATA] = [ map { $arr_cand->[DATA]{$_} } sort keys %{$arr_cand->[DATA]} ];
        }
        if( $args->{reverse} ) {
            @accepted_cand_data = reverse @accepted_cand_data;
        }

        if( $args->{limit} ) {
            if( $args->{skip} ) {
                if( $args->{skip} > @accepted_cand_data ) {
                    @accepted_cand_data = ();
                } else {
                    @accepted_cand_data = @accepted_cand_data[$args->{skip}..$#accepted_cand_data];
                }
            }
            $#accepted_cand_data = $args->{limit} if $args->{limit} > @accepted_cand_data;
        }

        return \@accepted_cand_data;
    } #if host obj found

    return [];
} #paginate

#
# Saves the object data for object $id to the data store.
#
sub stow {
    my( $self, $id, $class, $data ) = @_;

    my $save_data = "$class " . to_json($data);
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
    return $store->put_record( $store_idx, [$save_data] );
} #stow

#
# Takes a list of object data references and stows them all in the datastore.
# returns how many are stowed.
#
sub stow_all {
    my( $self, $objs ) = @_;
    my $count = 0;
    for my $o ( @$objs ) {
        $count += $self->stow( @$o );
    }
    return $count;
} #stow_all

# -------------------- private

#
# Return true if the obj matches the criteria.
#    search_terms   - a list of terms to match
#    search_fields  - if given, must be same size as search_terms
#                     searches each field in this list with the matching
#                     term from the search_terms at the same index.
#                     if present, hashkey_search is ignored.
#    hashkey_search - search on the field names rather than the fields.
#                     Makes no sense if search_fields is given.
#
sub _matches {
    my( $self, $obj_data, $search_terms, $search_fields, $hashkey_search ) = @_;
    
    return 1 unless @$search_terms;

    #
    # quick check. If no search term is found in the raw ( json string )
    # data of the object, then there can be no match.
    # 
    my $has = 0;
    for my $term (@$search_terms) {
        if( index( $obj_data->[RAW_DATA], $term ) > -1 ) {
            $has = 1;
            last;
        }
    }
    return 0 unless $has;
    my $data = from_json( $obj_data->[RAW_DATA] );
    my $is_arry = $obj_data->[CLASS] eq 'ARRAY';
    if( @$search_fields ) {
        for my $search_idx (0..$#$search_fields) {
            my $fld = $is_arry ? $data->[ $search_fields->[0] ] : 
                $data->{ $search_fields->[0] };
            return 1 if $fld =~ /^v.*$search_terms->[$search_idx]/;
        }
    } 
    else {
        my( @field_data ) = ($is_arry ? @$data : $hashkey_search ? keys %$data : values %$data );
        for my $fld (@field_data) {
            for my $search_term (@$search_terms) {
                return 1 if $fld =~ /^v.*$search_term/;
            }
        }
    }
    return 0;
} #_matches

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
    die "hash_fetch called for array" if ref( $obj->[DATA] ) eq 'ARRAY';
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
