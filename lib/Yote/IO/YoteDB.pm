package Yote::IO::YoteDB;

use strict;
use warnings;

no warnings 'uninitialized';

use Yote::IO::FixedStore;
use Yote::IO::StoreManager;

use Devel::FindRef;

use File::Path qw(make_path);
use JSON;

use Devel::Refcount 'refcount';

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
  make_path( $args->{ store } ) unless -d $args->{ store };
  my $filename = "$args->{ store }/OBJ_INDEX";
  # LII template is a long ( for object id, then the table id, then the index in that table
  return bless {
                args          => $args,
                OBJ_INDEX     => new Yote::IO::FixedRecycleStore( "LII", $filename ),
                STORE_MANAGER => new Yote::IO::StoreManager( $args ),
               }, $class;
} #new

# ------------------------------------------------

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
  if ( $obj ) {
    my $id = $obj->[CLASS] eq 'ARRAY' ? $obj->[DATA][$container_name] : $obj->[DATA]{$container_name};
    if ( $id =~ /^\d+$/ ) {
      my $container = $self->fetch( $id );
      if ( $container ) {
        return $container->[CLASS];
      }
    }
  }
  return '';
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
  if ( $obj ) {
    my $odata  = $obj->[DATA];
    my $terms  = $args->{ search_terms } || [];
    my $fields = $args->{ search_fields } || [];
    my $hashkey_search = $args->{ hashkey_search };

    if ( @$fields ) {
      return scalar(
                    grep { $self->_matches( $_, $terms, $fields, $hashkey_search ) }
                    map { $self->_fetch($_) }
                    grep { ! /^v/ }
                    ($obj->[CLASS] eq 'ARRAY' ? @$odata : values %$odata)
                   );
    } elsif ( @$terms ) {
      my $count = 0;
      my( @cands ) = ($obj->[CLASS] eq 'ARRAY' ? @$odata : $hashkey_search ? keys %$odata : values %$odata );
      for my $cand (@cands) {
        $count++ if grep { $cand =~ /$_/ } @$terms;
      }
      return $count;
    }
    return scalar($obj->[CLASS] eq 'ARRAY' ? @$odata : values %$odata);
  }
  return 0;
} #count

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
  if ( $OI->entries < 1 ) {
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


#
# Add the value or id to the list, at an optional index.
# Will die if the list_id does not point to a list.
#
sub list_insert {
  my( $self, $list_id, $val, $idx ) = @_;
  my $obj = $self->fetch( $list_id ) || [ $list_id, 'ARRAY', [] ];
  if ( ref( $obj->[DATA] ) ne 'ARRAY' ) {
    $obj->[DATA]{ $idx } = $val;
  } else {
    if ( defined( $idx ) && $idx < @{$obj->[DATA]} ) {
      splice @{$obj->[DATA]}, $idx, 0, $val;
    } else {
      push @{$obj->[DATA]}, $val;
    }
  }
  $self->stow( @$obj );
  return;
} #list_insert

sub max_id {
  return shift->{OBJ_INDEX}->entries;
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
#    sort           -  with non field sort, sorts alphabetically if 1
#    numeric        -  with non field sort, sorts numerically if 1 and sort is given
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
  my $return_hash = $args->{return_hash};
  if ( $obj ) {
    my $odata           = $obj->[DATA];
    my $search_terms    = $args->{ search_terms }  || [];
    my $search_fields   = $args->{ search_fields } || [];
    my $sort_fields     = $args->{ sort_fields }   || [];
    my $reversed_orders = $args->{ reversed_orders }   || [];
    my $hashkey_search  = $args->{ hashkey_search } || [];
    die "Number of search terms must mach number of search fields" if @$search_fields && @$search_fields != @$search_terms;
    my( $skip, $limit, $reverse, $sort, $numeric ) = @$args{ 'skip', 'limit', 'reverse', 'sort', 'numeric' };

    $skip //= 0;
    my $is_array = $obj->[CLASS] eq 'ARRAY';

    my $cand_keys = $is_array ? [0..$#$odata] : [sort keys %$odata];

    if ( (@$search_terms&&@$search_fields == 0) || @$hashkey_search ) {
      my( @new_keys );
      if ( @$search_terms && @$search_fields == 0 ) {
        for my $cand (@$cand_keys) {
          my $cval = $is_array ? $odata->[$cand] : $odata->{$cand};
        TERM:
          for my $term (@$search_terms) {
            if ( $cval =~ /^v.*$term/i ) {
              push @new_keys, $cand;
              last TERM;
            }
          }
        } #each cand
      } #if tosearch
      else {
        @new_keys = @$cand_keys;
      }
      if ( @$hashkey_search ) {
        my @new_new_keys;
        for my $cand (@new_keys) {
        H_TERM:
          for my $term (@$hashkey_search) {
            if ( $cand =~ /$term/i ) {
              push @new_new_keys, $cand;
              last H_TERM;
            }
          }
        } #each cand
        (@new_keys) = @new_new_keys;
      } #if tosearch

      $cand_keys = \@new_keys;
    } # if a hashkey or search term


    # this branch, objects ar esorted or searched
    if ( @$sort_fields || @$search_fields ) {
      # limit to results having objects behind them

      $cand_keys = [
                    grep { scalar($is_array ? $odata->[$cand_keys->[$_]] : $odata->{$cand_keys->[$_]} ) !~ /^v/ } (0..$#$cand_keys)];

      my( @newc, %cdata );
      for (@$cand_keys) {
        my $cand_data = $self->_fetch( $is_array ? $odata->[$_] : $odata->{$_} );
        if ( $self->_matches( $cand_data, $search_terms, $search_fields ) ) {
          push @newc, $_;
          $cand_data->[DATA] = from_json( $cand_data->[DATA] );
          if ( $cand_data->[CLASS] eq 'ARRAY' ) { #convert to hashes just for simplicity in comparing
            my $arry = $cand_data->[DATA];
            $cand_data->[DATA] = { map { $_ => $arry->[$_] } (0..$#$arry) };
          }
          $cdata{ $cand_data->[ID] } = $cand_data;
        }
      }
      $cand_keys = \@newc;

      my $numeric_fields = $args->{ numeric_fields } || [];
      for my $fld_idx ( 0..$#$sort_fields ) {
        my $fld = $sort_fields->[ $fld_idx ];
        if ( $reversed_orders->[ $fld_idx ] ) {
          if ( $is_array ) {
            if ( $numeric_fields->[ $fld_idx ] ) {
              $cand_keys = [ sort { substr( $cdata{$odata->[$b]}[DATA]{$fld}, 1 ) <=>
                                      substr( $cdata{$odata->[$a]}[DATA]{$fld}, 1 ) } (@$cand_keys) ];
            } else {
              $cand_keys = [ sort { $cdata{$odata->[$b]}[DATA]{$fld} cmp $cdata{$odata->[$a]}[DATA]{$fld} } (@$cand_keys) ];
            }
          } else {
            if ( $numeric_fields->[ $fld_idx ] ) {
              $cand_keys = [ sort { substr( $cdata{$odata->{$b}}[DATA]{$fld}, 1 ) <=>
                                      substr( $cdata{$odata->{$a}}[DATA]{$fld}, 1 ) } (@$cand_keys) ];
            } else {
              $cand_keys = [ sort { $cdata{$odata->{$b}}[DATA]{$fld} cmp $cdata{$odata->{$a}}[DATA]{$fld} } (@$cand_keys) ];
            }
          }
        } else {
          if ( $is_array ) {
            if ( $numeric_fields->[ $fld_idx ] ) {
              $cand_keys = [ sort { substr( $cdata{$odata->[$a]}[DATA]{$fld}, 1 ) <=>
                                      substr( $cdata{$odata->[$b]}[DATA]{$fld}, 1 ) } (@$cand_keys) ];
            } else {
              $cand_keys = [ sort { $cdata{$odata->[$a]}[DATA]{$fld} cmp $cdata{$odata->[$b]}[DATA]{$fld} } (@$cand_keys) ];
            }
          } else {
            if ( $numeric_fields->[ $fld_idx ] ) {
              $cand_keys = [ sort { substr( $cdata{$odata->{$a}}[DATA]{$fld}, 1 ) <=>
                                      substr( $cdata{$odata->{$b}}[DATA]{$fld}, 1 ) } (@$cand_keys) ];
            } else {
              $cand_keys = [ sort { $cdata{$odata->{$a}}[DATA]{$fld} cmp $cdata{$odata->{$b}}[DATA]{$fld} } (@$cand_keys) ];
            }
          }
        }
      } #sort
    } #end if sort or search fields
    elsif ( $sort || $numeric ) {
      if ( $is_array ) {
        if ( $numeric ) {
          $cand_keys = [ sort { substr( $odata->[$a], 1 ) <=> substr( $odata->[$b], 1 ) } @$cand_keys ];
        } else {
          $cand_keys = [ sort { $odata->[$a] cmp $odata->[$b] } @$cand_keys ];
        }
      } elsif ( $numeric ) {
          $cand_keys = [ sort { $a <=> $b } @$cand_keys ];
      } else {
        $cand_keys = [ sort { $odata->{$a} cmp $odata->{$b} } @$cand_keys ];
      }
    }

    if ( $reverse ) {
      $cand_keys = [ reverse @$cand_keys ];
    }
    if ( defined( $limit ) ) {
      $skip += 0;
      my $to = $skip + ( $limit - 1 );
      $to = $to > $#$cand_keys ? $#$cand_keys : $to;
      $cand_keys =  [@$cand_keys[$skip..$to]];
    }
    if ( $return_hash ) {
      if ( $is_array ) {
        return { map { $cand_keys->[$_] => $odata->[$cand_keys->[$_]] } (0..$#$cand_keys) };
      }
      return { map { $cand_keys->[$_] => $odata->{$cand_keys->[$_]} } (0..$#$cand_keys) };
    } elsif ( $is_array ) {
      return [ map { $odata->[$_] } @$cand_keys ];
    }

    return [map { $odata->{$_} } @$cand_keys];

  } #if obj
  return {} if $return_hash;
  return [];
} #paginate

sub get_recycled_ids {
  return shift->{OBJ_INDEX}->get_recycled_ids;
}

sub recycle_objects {
  return shift->_recycle_objects;
} #recycle_objects

sub _recycle_objects {
  my( $self, $keep_id, $keep_store ) = @_;
  my $is_first = 0;
  unless( $keep_id ) {
    $keep_id //= $self->first_id;
    $is_first = 1;
  }
  unless( $keep_store ) {
    # todo ... pick randomized name as this is temporary
    $keep_store = new Yote::IO::FixedStore( "I", $self->{args}{store} . '/RECYCLE' ),
      $keep_store->ensure_entry_count( $self->{OBJ_INDEX}->entries );

    # the already deleted cannot be re-recycled
    my $ri = $self->{OBJ_INDEX}->get_recycled_ids;
    for ( @$ri ) {
      $keep_store->put_record( $_, [ 1 ] );
    }
  }
  my( $has ) = @{ $keep_store->get_record( $keep_id ) };
  return if $has;

  $keep_store->put_record( $keep_id, [ 1 ] );
  my( @queue );
  my $item = $self->fetch( $keep_id );
  if ( ref( $item->[DATA] ) eq 'ARRAY' ) {
    ( @queue ) = grep { /^[^v]/ } @{$item->[DATA]};
  } else {
    ( @queue ) = grep { /^[^v]/ } values %{$item->[DATA]};
  }
  for my $keeper ( @queue ) {
    $self->_recycle_objects( $keeper, $keep_store );
  }
  if ( $is_first ) {
    # the purge begins here
    my $count = 0;
    my $cands = $self->{OBJ_INDEX}->entries;

    my( %weak_only_check, @weaks, %weaks );
    for ( 1..$cands) { #iterate each id in the entire object store
      my( $rec ) = @{ $keep_store->get_record( $_ ) };
      my $wf = $Yote::ObjProvider::WEAK_REFS->{$_};

      #OKEY, we have to fight cicular references. if an object in weak reference only references other things in
      # weak references, then it can be removed";
      if ( ! $rec ) {
        if( $wf ) {
          push @weaks, [ $_, $wf ];
          $weak_only_check{ $_ } = 3; # ref in @weaks, plus iter ref
        }
        else { #this case is something in the db that is not connected to the root and not loaded anywhere
          ++$count;
print STDERR Data::Dumper->Dump(["DELETER $_"]) if $_ == 104;
          $self->{OBJ_INDEX}->delete( $_, 1 );
        }
      }
    }
    # check things attached to the weak refs.
    for my $wf (@weaks) { 
      my( $id, $obj ) = @$wf;
      if ( ref( $obj ) eq 'ARRAY' ) { 
        for ( grep { $weak_only_check{$_} } map { Yote::ObjProvider::xform_in($_) } @$obj ) {
            print STDERR Data::Dumper->Dump(["ref $obj --> $_"]);
          $weak_only_check{ $_ }++;
        }
      } elsif ( ref( $obj ) eq 'HASH' ) {
        for ( grep { $weak_only_check{$_} } map { Yote::ObjProvider::xform_in($_) } values %$obj) {
            print STDERR Data::Dumper->Dump(["ref $obj --> $_"]);
          $weak_only_check{ $_ }++;
        }
      } else {
        for ( grep { $weak_only_check{$_} } values %{$obj->{DATA}} ) {
            print STDERR Data::Dumper->Dump(["ref $obj --> $_"]);
          $weak_only_check{ $_ }++;
        }
      }
    } #each weak

#    print STDERR Data::Dumper->Dump([[map { "$_->[0] : " . refcount($_->[1])." d: $Yote::ObjProvider::DIRTY->{$_->[0]} w: $Yote::ObjProvider::WEAK_REFS->{$_->[0]} woc:$weak_only_check{$_->[0]}" } @weaks],\%weak_only_check,"WEAKS"]);

    # can delete things with only references to the WEAK and DIRTY caches.
    my( @to_delete );
    for my $weak ( @weaks ) {
        my( $id, $obj ) = @$weak;
        delete $Yote::ObjProvider::WEAK_REFS->{$id};
#delete from WEAK_REFS before doing anything. might have to put it back on
#      if( $weak_only_check{$_} > (refcount(  - ( ref($Yote::ObjProvider::DIRTY->{$_}) ? 1 : 0 ) )) {
        print STDERR Data::Dumper->Dump(["Check $obj (found vs refcount) $id : $weak_only_check{$id} vs ".refcount($weak->[1])]);

        print STDERR Devel::FindRef::track \$obj;

        if( $weak_only_check{$id} >= refcount($weak->[1]) ) {
            push @to_delete, $id;
            ++$count;
        }
        else {
            $Yote::ObjProvider::WEAK_REFS->{$id} = $weak->[1];
        }
    }
    for( @to_delete ) {print STDERR Data::Dumper->Dump(["DELETE $_"]) if $_ == 104;
        $self->{OBJ_INDEX}->delete( $_, 1 );
        delete $Yote::ObjProvider::WEAK_REFS->{$_};
    }

    # remove recycle datastore
    $keep_store->unlink;

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
  if ( $current_store_id ) {
    my $old_store = $self->{STORE_MANAGER}->get_store( $current_store_id );
    if ( $old_store->{SIZE} >= $save_size ) {
      $old_store->put_record( $current_store_idx, [$save_data] );
      return;
    }
    $old_store->delete( $current_store_idx, 1 );
  }

  # find a store large enough and store it there.
  my( $store_id, $store ) = $self->{STORE_MANAGER}->best_store_for_size( $save_size );
  my $store_idx = $store->next_id;

  # okey, looks like the providing the next index is not working well with the recycling. is providing the same one?

  $self->{OBJ_INDEX}->put_record( $id, [ $store_id, $store_idx ] );

  my $ret = $store->put_record( $store_idx, [$save_data] );

  return $ret;
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
    if ( index( lc($obj_data->[RAW_DATA]), lc($term) ) > -1 ) {
      $has = 1;
      last;
    }
  }
  return 0 unless $has;
  my $data = from_json( $obj_data->[RAW_DATA] );
  my $is_arry = $obj_data->[CLASS] eq 'ARRAY';
  if ( @$search_fields ) {
    for my $search_idx (0..$#$search_fields) {
      my $fld = $is_arry ? $data->[ $search_fields->[$search_idx] ] :
        $data->{ $search_fields->[$search_idx] };
      return 1 if $fld =~ /^v.*$search_terms->[$search_idx]/;
    }
  } else {
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
  my $obj = $self->fetch( $hash_id ) || [ $hash_id, 'HASH', {} ];

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
  if ( $val ) {
    ( $actual_index ) = grep { $list->[$_] eq $val  } (0..$#$list);
  }
  splice( @$list, $actual_index, 1 ) if $#$list >= $actual_index;
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
