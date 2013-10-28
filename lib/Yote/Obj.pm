package Yote::Obj;

use strict;
use warnings;
no warnings 'uninitialized';

#
# This is base class for all Yote objects.
#
# It is a container class with fields and methods.
#
# On the server side :
#
#   The fields can be accessed with get_, like 'get_foo();' or 'get_foo( $initializer )'
#      A getter takes an optional initialization object
#      that is only used if the field has not yet been defined
#
#   The fields can be set with set_ like 'set_foo( "value" )'.
#
#   Lists can be added by by add_to_, like 'add_to_mylist( 'a', 2, $obj );'
#
#   Items can be removed from lists with remove_from_,  like 'remove_from_list( 2 );'
#
# On the client side :
#
#   methods may be invoked if they do not start with an underscore.
#
#   data may be accessed if it does not start with an underscore
#
#   data may be written to if it starts with a capitol letter
#

use Yote::ObjProvider;

use vars qw($VERSION);

$VERSION = '0.072';

# ------------------------------------------------------------------------------------------
#      * INITIALIZATION *
# ------------------------------------------------------------------------------------------

sub new {
    my( $pkg, $id_or_hash ) = @_;
    my $class = ref($pkg) || $pkg;

    my $obj;
    if( ref( $id_or_hash ) eq 'HASH' ) {
	$obj = bless {
	    ID       => undef,
	    DATA     => {},
	}, $class;
    }
    else {
	$obj = bless {
	    ID       => $id_or_hash,
	    DATA     => {},
	}, $class;
    }

    if( ! defined( $obj->{ID} ) ) {
	$obj->{ID} = Yote::ObjProvider::get_id( $obj );
	$obj->_init();
	Yote::ObjProvider::dirty( $obj, $obj->{ID} );
    }

    if( ref( $id_or_hash ) eq 'HASH' ) {
	for my $key ( keys %$id_or_hash ) {
	    $obj->{DATA}{$key} = Yote::ObjProvider::xform_in( $id_or_hash->{ $key } );
	}
	Yote::ObjProvider::dirty( $obj, $obj->{ID} );
    }

    return $obj;
} #new

#
# Called the very first time this object is created. It is not called
# when object is loaded from storage.
#
sub _init {}

#
# Called each time the object is loaded from the data store.
#
sub _load {}

# ------------------------------------------------------------------------------------------
#      * UTILITY METHODS *
# ------------------------------------------------------------------------------------------


#
# Takes the entire key/value pairs of data as field/value pairs attached to this.
#
sub _absorb {
    my $self = shift;
    my $data = ref( $_[0] ) ? $_[0] : { @_ };

    my $updated_count = 0;
    for my $fld (keys %$data) {
        my $inval = Yote::ObjProvider::xform_in( $data->{$fld} );
        Yote::ObjProvider::dirty( $self, $self->{ID} ) if $self->{DATA}{$fld} ne $inval;
        $self->{DATA}{$fld} = $inval;
        ++$updated_count;
    } #each field
    return $updated_count;
} #_absorb

# adds the items to the list attached to this object with the given name.
sub _add_to {
    my( $self, $listname, @data ) = @_;
    my $list_id = $self->{DATA}{$listname};
    if( $list_id ) {
	Yote::ObjManager::mark_dirty( $list_id );
    }
    else {
	my $func = "set_$listname";
	$self->$func( [] );
    }
    $list_id ||= $self->{DATA}{$listname};
    for my $d (@data) {
	Yote::ObjProvider::list_insert( $list_id, $d );
    }
    my $list = $Yote::ObjProvider::DIRTY->{ $list_id } || $Yote::ObjProvider::WEAK_REFS->{ $list_id };
    if( $list ) {
	push @$list, @data;
    }
    return;
} #_add_to

sub _insert_at {
    my( $self, $listname, $item, $idx ) = @_;
    my $list_id = $self->{DATA}{$listname};
    if( $list_id ) {
	Yote::ObjManager::mark_dirty( $list_id );
    }
    else {
	my $func = "set_$listname";
	$self->$func( [] );
    }
    $list_id ||= $self->{DATA}{$listname};
    Yote::ObjProvider::list_insert( $list_id, $item, $idx );
    my $list = $Yote::ObjProvider::DIRTY->{ $list_id } || $Yote::ObjProvider::WEAK_REFS->{ $list_id };
    if( $list ) {
	if( @$list <= $idx ) {
	    push @$list, $item;
	}
	else {
	    splice @$list, $idx, 0, $item;
	}
    }
    return;
} #_insert_at

# returns true if the object passsed in is the same as this one.
sub _is {
    my( $self, $obj ) = @_;
    return ref( $obj ) && ref( $obj ) eq ref( $self ) &&
        Yote::ObjProvider::get_id( $obj ) eq Yote::ObjProvider::get_id( $self );
}

# fetches from ObjProvider
sub _fetch {
    my( $self, $obj_id ) = @_;
    return Yote::ObjProvider::fetch( $obj_id );
} #_fetch

# just asks the object provider to return the id for the given item
sub _get_id {
    my( $self, $obj ) = @_;
    return Yote::ObjProvider::get_id( $obj );
} #_get_id

# anyone may read and edit public ( not starting with _ ) fields.
# only root may chnage the data field type ( like from scalar to containre )
sub _check_access {
    my( $self, $account, $write_access, $name ) = @_;

    return index( $name, '_' ) || ( $account && $account->get_login()->is_root() );

} #_check_access

# anyone may read and write public ( not starting with _ ) fields.
sub _check_access_update {
    my( $self, $account, $write_access, $data ) = @_;
    for my $key ( keys %$data ) {
	return 0 unless $self->_check_access( $account, $write_access, $key );
    }
    return 1;
} #_check_access

sub _count {
    my( $self, $args ) = @_;
    if( ref( $args ) ) {
	return Yote::ObjProvider::count( $self->{DATA}{$args->{name}}, $args );
    }
    return Yote::ObjProvider::count( $self->{DATA}{$args} );
} #_count

sub _hash_delete {
    my( $self, $hashname, $key ) = @_;
    my $hash_id = $self->{DATA}{$hashname};
    if( $hash_id ) {
	Yote::ObjManager::mark_dirty( $hash_id );
    }
    my $ret = Yote::ObjProvider::hash_delete( $hash_id, $key );

    my $hash = $Yote::ObjProvider::DIRTY->{ $hash_id } || $Yote::ObjProvider::WEAK_REFS->{ $hash_id };
    if( $hash ) {
	delete $hash->{ $key };
    }

    return $ret;
} #_hash_delete

sub _hash_insert {
    my( $self, $hashname, $key, $val ) = @_;
    my $hash_id = $self->{DATA}{$hashname};
    if( $hash_id ) {
	# mark dirty here in case there are outstanding instances of that hash?
	Yote::ObjManager::mark_dirty( $hash_id );

	Yote::ObjProvider::hash_insert( $hash_id, $key, $val );
	my $hash = $Yote::ObjProvider::DIRTY->{ $hash_id } || $Yote::ObjProvider::WEAK_REFS->{ $hash_id };
	if( $hash ) {
	    $hash->{ $key }= $val;
	}
	return $val;
    }
    my $fun = "set_$hashname";
    
    return $self->$fun( { $key => $val } );
} #_hash_insert

sub _hash_fetch {
    my( $self, $hashname, $key ) = @_;
    return Yote::ObjProvider::hash_fetch( $self->{DATA}{$hashname}, $key );
}

sub _list_delete {
    my( $self, $listname, $idx ) = @_;
    my $list_id = $self->{DATA}{$listname};
    return unless $list_id;
    Yote::ObjManager::mark_dirty( $list_id );
    Yote::ObjProvider::list_delete( $list_id, $idx );
    my $list = $Yote::ObjProvider::DIRTY->{ $list_id } || $Yote::ObjProvider::WEAK_REFS->{ $list_id };
    if( $list ) {
	splice @$list, $idx, 1;
    }
    return;
} #_list_delete

sub _list_fetch {
    my( $self, $listname, $key ) = @_;
    return Yote::ObjProvider::list_fetch( $self->{DATA}{$listname}, $key );
}

sub _lock {
    my $self = shift;
    return Yote::ObjProvider::lock( $self->{ID}, $self );
} #lock

sub _unlock {
    my $self = shift;
    return Yote::ObjProvider::unlock( $self->{ID} );
} #_unlock

sub _hash_has_key {
    my( $self, $hashname, $key ) = @_;
    return Yote::ObjProvider::hash_has_key( $self->{DATA}{$hashname}, $key );
}

sub _paginate {
    my( $self, $args ) = @_;
    return Yote::ObjProvider::paginate( $self->{DATA}{$args->{name}}, $args );
} #_paginate

sub _power_clone {
    my( $self, $replacements ) = @_;
    return Yote::ObjProvider::power_clone( $self, $replacements );
}

sub _remove_from {
    my( $self, $listname, @data ) = @_;
    my $list_id = $self->{DATA}{$listname};
    return unless $list_id;
    
    for my $d (@data) {
	Yote::ObjProvider::remove_from( $list_id, $d );
    }
    my $list = $Yote::ObjProvider::DIRTY->{ $list_id } || $Yote::ObjProvider::WEAK_REFS->{ $list_id };
    if( $list ) {
	for( my $i=0; $i < @$list; $i++ ) {
	    splice @$list, $i, 1 if grep { $list->[$i] eq $_ } @data;
	}
    }    
    Yote::ObjManager::mark_dirty( $list_id );
} #_remove_from

#
# Private method to update the hash give. Returns if things were made dirty.
# Takes a list of fields to try to extract from the hash.
#
sub _update {
    my( $self, $datahash, @fieldlist ) = @_;

    my $dirty;
    if( @fieldlist ) {
	for my $fld ( @fieldlist ) {
	    my $set = "set_$fld";
	    my $get = "get_$fld";
	    if( defined( $datahash->{ $fld } ) ) {
		$dirty = $dirty || $self->$get() eq $datahash->{ $fld };
		$self->$set( $datahash->{ $fld });
	    }
	}
    }
    else {
	# catch anything tossed in that does not start with underscore
	for my $fld ( keys %$datahash ) {
	    my $set = "set_$fld";
	    my $get = "get_$fld";
	    $dirty = $dirty || $self->$get() eq $datahash->{ $fld };
	    $self->$set( $datahash->{ $fld } );
	}
    }
    Yote::ObjProvider::dirty( $self, $self->{ID} ) if $dirty;

    return $dirty;
} #_update

# ------------------------------------------------------------------------------------------
#      * PUBLIC METHODS *
# ------------------------------------------------------------------------------------------


sub add_to {
    my( $self, $args, $account ) = @_;
    die "Access Error" unless $self->_check_access( $account, 1, $args->{ name } );
    my( $listname, $items ) = @$args{'name','items'};
    return $self->_add_to( $listname, @$items );
} #add_to

sub count {
    my( $self, $data, $account ) = @_;
    die "Access Error" unless $self->_check_access( $account, 0, ref( $data ) ? $data->{ name } : $data );
    return $self->_count( $data );
} #count

sub delete_key {
    my( $self, $args, $account ) = @_;
    die "Access Error" unless $self->_check_access( $account, 1, $args->{ name } );
    my( $listname, $key ) = @$args{'name','key'};
    return $self->_hash_delete( $args->{name}, $key );
} #delete_key

sub hash {
    my( $self, $args, $account ) = @_;
    die "Access Error" unless $self->_check_access( $account, 1, $args->{ name } );
    my( $name, $key, $val ) = @$args{'name','key','value'};

    return $self->_hash_insert( $name, $key, $val );
} #hash

sub hash_fetch {
    my( $self, $args, $account ) = @_;
    die "Access Error" unless $self->_check_access( $account, 0, $args->{ name } );
    my( $name, $key ) = @$args{'name','key'};

    return $self->_hash_fetch( $name, $key );
} #hash_fetch

sub insert_at {
    my( $self, $args, $account ) = @_;
    die "Access Error" unless $self->_check_access( $account, 1, $args->{ name } );
    my( $listname, $idx, $item ) = @$args{'name','index','item'};
    return $self->_insert_at( $listname, $item, $idx );
} #insert_at

sub list_delete {
    my( $self, $args, $account ) = @_;
    die "Access Error" unless $self->_check_access( $account, 1, $args->{ name } );
    return $self->_list_delete( $args->{name}, $args->{index} );
} #list_delete

sub list_fetch {
    my( $self, $args, $account ) = @_;
    die "Access Error" unless $self->_check_access( $account, 0, $args->{ name } );
    return $self->_list_fetch( $args->{name}, $args->{index} );
} #list_fetch

sub paginate {
    my( $self, $args, $account ) = @_;
    die "Access Error" unless $self->_check_access( $account, 0, $args->{ name } );
    return Yote::ObjProvider::paginate( $self->{DATA}{ $args->{name} }, $args );
} #paginate

sub remove_from {
    my( $self, $args, $account ) = @_;
    die "Access Error" unless $self->_check_access( $account, 1, $args->{ name } );
    my( $listname, $items ) = @$args{'name','items'};
    return $self->_remove_from( $listname, @{$items||[]} );
} #remove_from

#
# This is actually a no-op, but has the effect of giving the client any objects that have changed since the clients last call.
#
sub sync_all {}

#
# Stub method to apply update to an object. Throws an error by default. Override and call _update with input data and a list of allowed fields to update.
#
sub update {
    my( $self, $data, $acct ) = @_;
    die "Access Error" unless $self->_check_access_update( $acct, 1, $data );
    return $self->_update( $data );
} #update


#
# Defines get_foo, set_foo, add_to_list, remove_from_list
#
sub AUTOLOAD {
    my( $s, $arg ) = @_;
    my $func = our $AUTOLOAD;

    if( $func =~/:add_to_(.*)/ ) {
        my( $fld ) = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, @vals ) = @_;
            my $get = "get_$fld";
            my $arry = $self->$get([]); # init array if need be
	    push( @$arry, @vals );
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    } #add_to
    elsif( $func =~/:add_once_to_(.*)/ ) {
        my( $fld ) = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, @vals ) = @_;
            my $get = "get_$fld";
            my $arry = $self->$get([]); # init array if need be
	    for my $val ( @vals ) {
		unless( grep { $val eq $_ } @$arry ) {
		    push @$arry, $val;
		}
	    }
	};
        use strict 'refs';
        goto &$AUTOLOAD;
    } #add_once_to
    elsif( $func =~ /:remove_from_(.*)/ ) { #removes the first instance of the target thing from the list
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, @vals ) = @_;
            my $get = "get_$fld";
            my $arry = $self->$get([]); # init array if need be
	    for my $val (@vals ) {
		for my $i (0..$#$arry) {
		    if( $arry->[$i] eq $val ) {
			splice @$arry, $i, 1;
			last;
		    }
		}
	    }
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    }
    elsif( $func =~ /:remove_all_from_(.*)/ ) { #removes the first instance of the target thing from the list
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, @vals ) = @_;
            my $get = "get_$fld";
            my $arry = $self->$get([]); # init array if need be
	    for my $val (@vals) {
		my $count = grep { $_ eq $val } @$arry;
		while( $count ) {
		    for my $i (0..$#$arry) {
			if( $arry->[$i] eq $val ) {
			    --$count;
			    splice @$arry, $i, 1;
			    last unless $count;
			}
		    }
		}
	    }
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    }
    elsif ( $func =~ /:set_(.*)/ ) {
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, $val ) = @_;
            my $inval = Yote::ObjProvider::xform_in( $val );
            Yote::ObjProvider::dirty( $self, $self->{ID} ) if $self->{DATA}{$fld} ne $inval;
            $self->{DATA}{$fld} = $inval;

	    return Yote::ObjProvider::xform_out( $self->{DATA}{$fld} );
        };
        goto &$AUTOLOAD;
    }
    elsif( $func =~ /:get_(.*)/ ) {
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, $init_val ) = @_;
            if( ! defined( $self->{DATA}{$fld} ) && defined($init_val) ) {
                if( ref( $init_val ) ) {
                    Yote::ObjProvider::dirty( $init_val, Yote::ObjProvider::get_id( $init_val ) );
                }
                Yote::ObjProvider::dirty( $self, $self->{ID} );
                $self->{DATA}{$fld} = Yote::ObjProvider::xform_in( $init_val );
            }
            return Yote::ObjProvider::xform_out( $self->{DATA}{$fld} );
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    }
    else {
        die "Unknown Yote::Obj function '$func'";
    }

} #AUTOLOAD

sub DESTROY {}

1;
__END__

=head1 NAME

Yote::Obj - Base class for all persistant Yote objects.

=head1 DESCRIPTION

Yote::Obj is the base class for all stateful Yote objects that have an API presence
and will be stored in persistant.

This is a container class and all objects of this class have automatic getter and
setter methods for scalar and list entries. Invoking '$yote_obj->set_foo( "bar" );'
will cause a variable named 'foo' to be attached to this object and assigned the value
of "bar". The values that can be assigend are any number, string, hash, list or Yote::Obj
object. Calling 'my $val = $yote_obj->get_baz( "fred" )' will return the value of the
variable 'baz', and if none is defined, assigns the value "fred" to 'baz' and returns it.

Additionally, '$yote_obj->add_to_foo( "a", "b", "c", "c" )' will add the values 'a', 'b', 'c' and 'c'
to the list with the variable name 'foo' that is attached to this object. If no such variable
exists, a list will be created and assigned to it. If there already is a 'foo' that is not a list,
and error will not result. There are a counterpart methods '$yote_obj->remove_from_foo( "c" )' which
removes the first instance of c from the foo list, and '$yote_obj->remove_all_from_foo( "b" )' which
will remove all the "b" values from the 'foo' list.

All Yote objects have public api methods. These are methods that connect to javascript objects
and are invoked by clients. All the public api methods have the same signature :

All Yote objects except YoteRoot are attached to an application or descent of the Yote::AppRoot
class.

=over 2

public_api_method( $data, $account )

Where $data is either a scalar value, a list, hash or yote object. $account is the account assigned
to the user for the app that this yote object belongs to. $account may be undefined if the method
may be called by someone not logging in.

=back

=head2 A NOTE ON METHODS

There are different method types for yote :

=over 2

=item Public API methods

These methods are called automatically by the yote system and are not meant to be called by other subs.
The yote system automatically passes data given to the API and passes in the account of the logged in
user (if any), so the signature for these methods is always the same.


=item Automatic container methods

These are the methods that are automatic to any yote object. The 'foo', is of course, a stand in for
any data name.

* set_foo

* get_foo

* add_to_foo

* remove_from_foo

=item Utility methods

=item Initialization methods

These methods begin with an underscore. The underscore signals to yote to not broadcast this method to the
javascript proxy objects. The yote convention is a single underscore for a utility method that is called
by other methods in all packages, and a double underscore for 'private' methods.

=back

=head2 A NOTE ON DATA

Yote has 3 behaviors for data fields of Yote objects

=over 2

=item read only through api

If a field begins with a lowercase letter, the yote server will be transmitted it the javascript proxy
object, and will ignore any requests from the client to update its value.

=item read/write through api

If a field begins with a capital letter, it will be transmitted to the javascript proxy object, which
may send updates of its value back to the yote server.

=item private data field

If a field starts with an underscore, the yote server will not transmit it to the javascript proxy, and
will ignore any requests from the client to update its value.

=back

=head2 UTILITY METHODS

=over 4

=item _absorb

This takes a hash reference as an argument and uses the key/value entries in this hash to set
values for the fields corresponding to the hash keys.

=item _is

Returns true if the single object argument passed in is equivalent to this one.

=back

=head2 INITIALIZATION METHODS

=over 4

=item new

New takes an optional hash as an argument. If given a hash, it populates the object with the key value
pairs in the hash, as long as those are text/numbers,lists,hashes or yote objects. Note that while this
does not start with an underscore, it is still not exposed to the javascript yote objects.

=item _init

This is called once : only the very first time a Yote object is created. It is used to set up initial data.

=item _load

This method is called each time an object is loaded from the data store.

=back

=head2 PUBLIC API METHODS

=over 4

=item add_to( { name => '', items => [] } )

Adds the items to the list attached to this object specified by name.

=item count( field_name )

Returns the number of items for the field of this object provided it is an array or hash.

=item delete_key( { name => '', key => '' } )

Removes the key from the hash attached to this object specified by name.

=item hash( { name => '', key => '', value => item } )

Hashes the item to the key to the hash attached to this object specified by name.

=item insert_at( { name => '', index => '', item => item } )

Insert the item at the index to the list attached to this object specified by name.

=item list_delete( { name => '', index => '' } )

Removes the item at the index postion from the list attached to this object specified by name.

=item list_fetch( { name => '', index => '' } )

Returns item at the index postion from the list attached to this object specified by name.

=item paginate( args )

Returns a paginated list or hash. Arguments are

=item remove_from( { name => '', items => [] } )

Removes the items ( by value ) from the list attached to this object specified by name.

=over 4

* name - name of data structure attached to this object.
* search_fields - a list of fields to search for in collections of yote objects
* search_terms - a list of terms to search for
* sort_fields - a list of fields to sort by for collections of yote objects
* reversed_orders - a list of true or false values corresponding to the sort_fields list. A true value means that field is sorted in reverse
* limit - maximum number of entries to return
* skip - skip this many entries before returning the list
* return_hash - return the result as a hashtable rather than as a list
* reverse - return the result in reverse order

=back


=item sync_all

This method is actually a no-op, but has the effect of syncing the state of client and server.

=item update

This method is called automatically by a client javascript objet when its _send_update method is called.
It takes a hash ref filled with field name value pairs and updates the values that are read/write
( first character is a capital letter ).

=back

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf



This module is free software; it can be used under the same terms as perl
itself.

=cut
