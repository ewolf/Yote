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


use Yote::ObjManager;
use Yote::ObjProvider;

use vars qw($VERSION);

$VERSION = '0.071';

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
	for my $key ( %$id_or_hash ) {
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

sub _count {
    my( $self, $container_name ) = @_;
    return Yote::ObjProvider::count( $self->{DATA}{$container_name} );
}

sub _list_insert {
    my( $self, $listname, $val, $idx ) = @_;
    return Yote::ObjProvider::list_insert( $self->{DATA}{$listname}, $val, $idx );
}

sub _list_delete {
    my( $self, $listname, $idx ) = @_;
    return Yote::ObjProvider::list_delete( $self->{DATA}{$listname}, $idx );
}

sub _hash_delete {
    my( $self, $hashname, $key ) = @_;
    return Yote::ObjProvider::hash_delete( $self->{DATA}{$hashname}, $key );
}

sub _hash_insert {
    my( $self, $hashname, $key, $val ) = @_;
    return Yote::ObjProvider::hash_insert( $self->{DATA}{$hashname}, $key, $val );
} #_hash_insert

sub _hash_fetch {
    my( $self, $hashname, $key ) = @_;
    return Yote::ObjProvider::hash_fetch( $self->{DATA}{$hashname}, $key );
}

sub _list_fetch {
    my( $self, $listname, $key ) = @_;
    return Yote::ObjProvider::list_fetch( $self->{DATA}{$listname}, $key );
}

sub _hash_has_key {
    my( $self, $hashname, $key ) = @_;
    return Yote::ObjProvider::hash_has_key( $self->{DATA}{$hashname}, $key );
}

sub _power_clone {
    my( $self, $replacements ) = @_;
    return Yote::ObjProvider::power_clone( $self, $replacements );
}

#
# Private method to update the hash give. Returns if things were made dirty.
# Takes a list of fields to try to extract from the hash.
#
sub _update {
    my( $self, $datahash, @fieldlist ) = @_;

    my $dirty;
    for my $fld ( @fieldlist ) {
	my $set = "set_$fld";
	my $get = "get_$fld";
	if( defined( $datahash->{ $fld } ) ) {
	    $dirty = $dirty || $self->$get() eq $datahash->{ $fld };
	    $self->$set( $datahash->{ $fld });
	}
    }
    return $dirty;
} #_update

# ------------------------------------------------------------------------------------------
#      * UTILITY METHODS *
# ------------------------------------------------------------------------------------------

#
# These methods are not part of the public API
#


# ------------------------------------------------------------------------------------------
#      * PUBLIC METHODS *
# ------------------------------------------------------------------------------------------

sub count {
    my( $self, $data, $account ) = @_;

    if( index( $data, '_' ) == 0 && ! $account->get_login()->is_root() && ! ref( $account->get_login() ) ne 'Yote::Login' ) {
	die "permissions error";
    }
    return $self->_count( $data );
} #count

sub _paginate {
    my( $self, $args ) = @_;
    return Yote::ObjProvider::paginate( $self->{DATA}{$args->{name}}, $args );
} #_paginate

sub paginate {
    my( $self, $args, $account ) = @_;
    if( index( $args->{name}, '_' ) == 0 && ! $account->get_login()->is_root() && ! ref( $account->get_login() ) ne 'Yote::Login' ) {
	die "permissions error";
    }
    return Yote::ObjProvider::paginate( $self->{DATA}{ $args->{name} }, $args );
} #paginate

#
# This is actually a no-op, but has the effect of giving the client any objects that have changed since the clients last call.
#
sub sync_all {}


#
# Stub method to apply update to an object. Throws an error by default. Override and call _update with input data and a list of allowed fields to update.
#
sub update {
    die "Disallows update";
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
                $self->{DATA}{$fld} = Yote::ObjProvider::xform_in( $init_val );
                if( ref( $init_val ) ) {
                    Yote::ObjProvider::dirty( $init_val, $self->{DATA}{$fld} );
                }
                Yote::ObjProvider::dirty( $self, $self->{ID} );
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

=item count( field_name )

Returns the number of items for the field of this object provided it is an array or hash.

=item paginate_list

This method takes a list ref with three entries : [field_name, number of items to return, starting point].
The starting point is optional and defaults to 0. Returns a subset of the list that is specified by the
field name and attached to this object.

This will throw an error if the value of the field name is defined as something other than a list.

=item paginate_list_rev

This method is just like paginate except it works on the list in reverse order.
This method takes a list ref with three entries : [field_name, number of items to return, starting point].
The starting point is optional and defaults to 0. Returns a subset of the list that is specified by the
field name and attached to this object.

This will throw an error if the value of the field name is defined as something other than a list.

=item paginate_hash

This method takes a list ref with three entries : [field_name, number of items to return, starting point].
The starting point is optional and defaults to 0. Returns a slice of the hash that is specified by the
field name and attached to this object. The keys are sorted before the return so that the order can
be guaranteed between subsequent calls.

This will throw an error if the value of the field name is defined as something other than a list.

=item search_list

Returns a paginated search list

=item sync_all

This method is actually a no-op, but has the effect of syncing the state of client and server.

=item update

This method is called automatically by a client javascript objet when its _send_update method is called.
It takes a hash ref filled with field name value pairs and updates the values that are read/write
( first character is a capital letter ).

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
