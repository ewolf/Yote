package Yote::ObjProvider;

use strict;
use warnings;
no warnings 'numeric';
no warnings 'uninitialized';
no warnings 'recursion';

use Yote::Array;
use Yote::Cache;
use Yote::Hash;
use Yote::Obj;
use Yote::ObjManager;
use Yote::Root;
use Yote::IO::YoteDB;

use Crypt::Passwd::XS;
use WeakRef;

$Yote::ObjProvider::DIRTY          = {};
$Yote::ObjProvider::PKG_TO_METHODS = {};
$Yote::ObjProvider::WEAK_REFS      = {};

our $DATASTORE;
our $FIRST_ID;
our $CACHE;

use vars qw($VERSION);

$VERSION = '0.073';


# ------------------------------------------------------------------------------------------
#      * INIT METHODS *
# ------------------------------------------------------------------------------------------
sub new {
    my $ref = shift;
    my $class = ref( $ref ) || $ref;
    return bless {}, $class;
} #new

sub init {
    my $args = shift;
    $DATASTORE = new Yote::IO::YoteDB( $args );
    $DATASTORE->ensure_datastore();
    $CACHE = new Yote::Cache( $args );
} #init

# ------------------------------------------------------------------------------------------
#      * PUBLIC CLASS METHODS *
# ------------------------------------------------------------------------------------------

sub container_type {
    my( $host_id, $container_name ) = @_;
    return '' unless $host_id;
    return $DATASTORE->container_type( $host_id, $container_name ) || '';
} #container_type

sub count {
    my( $container_id, $args ) = @_;
    return 0 unless $container_id;
    return $DATASTORE->count( $container_id, $args );
}

#
# Markes given object as dirty.
#
sub dirty {
    my $obj = shift;
    my $id = shift;
    Yote::ObjManager::mark_dirty( $id );
    $Yote::ObjProvider::DIRTY->{$id} = $obj;
} #dirty

sub fetch {
    my( $id ) = @_;
    return undef unless $id;
    #
    # Return the object if we have a reference to its dirty state.
    #
    my $ref = $Yote::ObjProvider::DIRTY->{$id} || $Yote::ObjProvider::WEAK_REFS->{$id} || $CACHE->fetch($id);

    if( defined $ref ) {
        return $ref;
    }
    my $obj_arry = $DATASTORE->fetch( $id );

    if( $obj_arry ) {
        my( $id, $class, $data ) = @$obj_arry;
        if( $class eq 'ARRAY' ) {
            my( @arry );
            tie @arry, 'Yote::Array', $id, @$data;
            my $tied = tied @arry; $tied->[2] = \@arry;
            $CACHE->stow( $id, \@arry );
            __store_weak( $id, \@arry );
            return \@arry;
        }
        elsif( $class eq 'HASH' ) {
            my( %hash );
            tie %hash, 'Yote::Hash', $id, map { $_ => $data->{$_} } keys %$data;
            my $tied = tied %hash; $tied->[2] = \%hash;
            $CACHE->stow( $id, \%hash );
            __store_weak( $id, \%hash );
            return \%hash;
        }
        else {
            eval("require $class");
            return undef if $@;

            my $obj = $class->new( $id );
            $obj->{DATA} = $data;
            $obj->{ID} = $id;
            $obj->_load();
            $CACHE->stow( $id, $obj );
            __store_weak( $id, $obj );
            return $obj;
        }
    }

    return undef;
} #fetch


#
# Returns the first ID that is associated with the root Root object
#
sub first_id {
    $FIRST_ID ||= $DATASTORE->first_id();
    return $FIRST_ID;
}

sub flush {
    for my $id ( @_ ) {
        delete $Yote::ObjProvider::DIRTY->{$id};
        delete $Yote::ObjProvider::WEAK_REFS->{$id};
    }
}

sub flush_all_volatile {
    $Yote::ObjProvider::DIRTY = {};
    $Yote::ObjProvider::WEAK_REFS = {};
}


sub get_id {
    my $ref = shift;
    my $class = ref( $ref );
    if( $class eq 'Yote::Array') {
        return $ref->[0];
    }
    elsif( $class eq 'ARRAY' ) {
        my $tied = tied @$ref;
        if( $tied ) {
            $tied->[0] ||= $DATASTORE->get_id( "ARRAY" );
            __store_weak( $tied->[0], $ref );
            return $tied->[0];
        }
        my( @data ) = @$ref;
        my $id = $DATASTORE->get_id( $class );
        tie @$ref, 'Yote::Array', $id;
        $tied = tied @$ref; $tied->[2] = $ref;
        push( @$ref, @data );
        dirty( $ref, $id );
        __store_weak( $id, $ref );
        return $id;
    }
    elsif( $class eq 'Yote::Hash' ) {
        my $wref = $ref;
        return $ref->[0];
    }
    elsif( $class eq 'HASH' ) {
        my $tied = tied %$ref;
        if( $tied ) {
            $tied->[0] ||= $DATASTORE->get_id( "HASH" );
            __store_weak( $tied->[0], $ref );
            return $tied->[0];
        }
        my $id = $DATASTORE->get_id( $class );
        my( %vals ) = %$ref;
        tie %$ref, 'Yote::Hash', $id;
        $tied = tied %$ref; $tied->[2] = $ref;
        for my $key (keys %vals) {
            $ref->{$key} = $vals{$key};
        }
        dirty( $ref, $id );
        __store_weak( $id, $ref );
        return $id;
    }
    else {
        if( $class eq 'Yote::Root' ) {
            $ref->{ID} = $DATASTORE->first_id( $class );
        } else {
            $ref->{ID} ||= $DATASTORE->get_id( $class );
        }
        __store_weak( $ref->{ID}, $ref );
        return $ref->{ID};
    }

} #get_id

sub hash_delete {
    my( $hash_id, $key ) = @_;
    return $DATASTORE->hash_delete( $hash_id, $key );
}

sub hash_fetch {
    my( $hash_id, $key ) = @_;
    return xform_out( $DATASTORE->hash_fetch( $hash_id, $key ) );
} 

sub hash_has_key {
    my( $hash_id, $key ) = @_;
    return $DATASTORE->hash_has_key( $hash_id, $key );
}

sub hash_insert {
    my( $hash_id, $key, $val ) = @_;
    return $DATASTORE->hash_insert( $hash_id, $key, xform_in( $val ) );
} #hash_insert

sub list_delete {
    my( $list_id, $idx ) = @_;
    return $DATASTORE->list_delete( $list_id, undef, $idx );
}

sub list_fetch {
    my( $list_id, $idx ) = @_;
    return xform_out( $DATASTORE->list_fetch( $list_id, $idx ) );
} 

sub list_insert {
    my( $list_id, $val, $idx ) = @_;
    return $DATASTORE->list_insert( $list_id, xform_in( $val ), $idx );
}

sub package_methods {
    my $pkg = shift;
    my $methods = $Yote::ObjProvider::PKG_TO_METHODS{$pkg};
    unless( $methods ) {

        no strict 'refs';
        my @m = grep { $_ && $_ !~ /^(_.*|AUTOLOAD|BEGIN|DESTROY|ISA|VERSION|unix_std_crypt|is|add_(once_)?to_.*|remove_(all_)?from_.*|import|[sg]et_.*|can|isa|new|decode_base64|encode_base64)$/ } grep { $_ !~ /::/ } keys %{"${pkg}\::"};

        for my $class ( @{"${pkg}\::ISA" } ) {
            my $pm = package_methods( $class );
            push @m, @$pm;
        }
        $methods = \@m;
        $Yote::ObjProvider::PKG_TO_METHODS{$pkg} = $methods;
        use strict 'refs';
    }
    return $methods;
} #package_methods

sub paginate {
    my( $obj_id, $args ) = @_;
    if( $args->{ return_hash } ) {
        return {} unless $obj_id;
        my $res = $DATASTORE->paginate( $obj_id, $args );
        return { map { $_ => xform_out( $res->{$_} ) } sort keys %$res };
    }
    return [] unless $obj_id;
    return [ map { xform_out( $_ ) } @{ $DATASTORE->paginate( $obj_id, $args ) } ];
} #paginate

sub recycle_objects {
    $CACHE->purge();
    Yote::ObjProvider::stow_all();
    return $DATASTORE->recycle_objects( @_ );
} #recycle_objects

sub remove_from {
    my( $list_id, $item ) = @_;
    return $DATASTORE->list_delete( $list_id, xform_in( $item ) );
} #remove_from

sub stow {
    my( $obj ) = @_;

    my $class = ref( $obj );
    return unless $class;
    my $id = get_id( $obj );
    die unless $id;

    my $data = __raw_data( $obj );
    if( $class eq 'ARRAY' ) {
        $DATASTORE->stow( $id,'ARRAY', $data );
        __clean( $id );
    }
    elsif( $class eq 'HASH' ) {
        $DATASTORE->stow( $id,'HASH',$data );
        __clean( $id );
    }
    elsif( $class eq 'Yote::Array' ) {
        if( __is_dirty( $id ) ) {
            $DATASTORE->stow( $id,'ARRAY',$data );
            __clean( $id );
        }
        for my $child (@$data) {
            if( $child =~ /^[0-9]/ && $Yote::ObjProvider::DIRTY->{$child} ) {
                stow( $Yote::ObjProvider::DIRTY->{$child} );
            }
        }
    }
    elsif( $class eq 'Yote::Hash' ) {
        if( __is_dirty( $id ) ) {
            $DATASTORE->stow( $id, 'HASH', $data );
        }
        __clean( $id );
        for my $child (values %$data) {
            if( $child =~ /^[0-9]/ && $Yote::ObjProvider::DIRTY->{$child} ) {
                stow( $Yote::ObjProvider::DIRTY->{$child} );
            }
        }
    }
    else {
        if( __is_dirty( $id ) ) {
            $DATASTORE->stow( $id, $class, $data );
            __clean( $id );
        }
        for my $val (values %$data) {
            if( $val =~ /^[0-9]/ && $Yote::ObjProvider::DIRTY->{$val} ) {
                stow( $Yote::ObjProvider::DIRTY->{$val} );
            }
        }
    }
} #stow

sub stow_all {
    my @odata;
    for my $obj (values %{$Yote::ObjProvider::DIRTY} ) {
        my $cls;
        my $ref = ref( $obj );
        if( $ref eq 'ARRAY' || $ref eq 'Yote::Array' ) {
            $cls = 'ARRAY';
        } elsif( $ref eq 'HASH' || $ref eq 'Yote::Hash' ) {
            $cls = 'HASH';
        } else {
            $cls = $ref;
        }
        push( @odata, [ get_id( $obj ), $cls, __raw_data( $obj ) ] );
    }
    $DATASTORE->stow_all( \@odata );
    $Yote::ObjProvider::DIRTY = {};
} #stow_all

sub xform_in {
    my $val = shift;
    if( ref( $val ) ) {
        return get_id( $val );
    }
    return "v$val";
}

sub xform_out {
    my $val = shift;
    return undef unless defined( $val );
    if( index($val,'v') == 0 ) {
        return substr( $val, 1 );
    }
    return fetch( $val );
}



# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

sub __clean {
    my $id = shift;
    delete $Yote::ObjProvider::DIRTY->{$id};
} #__clean

sub __is_dirty {
    my $obj = shift;
    my $id = ref($obj) ? get_id($obj) : $obj;
    return $Yote::ObjProvider::DIRTY->{$id};
} #__is_dirty

#
# Returns data structure representing object. References are integers. Values start with 'v'.
#
sub __raw_data {
    my( $obj ) = @_;
    my $class = ref( $obj );
    return unless $class;
    my $id = get_id( $obj );
    die unless $id;
    if( $class eq 'ARRAY' ) {
        my $tied = tied @$obj;
        if( $tied ) {
            return $tied->[1];
        } else {
            die;
        }
    }
    elsif( $class eq 'HASH' ) {
        my $tied = tied %$obj;
        if( $tied ) {
            return $tied->[1];
        } else {
            die;
        }
    }
    elsif( $class eq 'Yote::Array' ) {
        return $obj->[1];
    }
    elsif( $class eq 'Yote::Hash' ) {
        return $obj->[1];
    }
    else {
        return $obj->{DATA};
    }
    
} #__raw_data

sub __store_weak {
    my( $id, $ref ) = @_;
    $Yote::ObjProvider::WEAK_REFS->{$id} = $ref;
    weaken( $Yote::ObjProvider::WEAK_REFS->{$id} );
} #__store_weak


1;
__END__

=head1 NAME

Yote::ObjProvider - Serves Yote objects. Configured to a persistance engine.

=head1 DESCRIPTION

This module is essentially a private module and its methods will not be called directly by programs.
This module is the front end for assigning IDs to objects, fetching objects, keeping track of objects that need saving (are dirty) and saving all dirty objects.
It is the only module to directly interact with the datastore layer.

=head1 INIT METHODS

=over 4

=item new

=item init - takes a hash of args, passing them to a new Yote::SQLite object and starting it up.


=back

=head1 CLASS METHODS

=over 4

=item container_type( host_id, container_name )

Returns the class name of the given container from a host class.
For example, if Yote::Obj $o has an array attached to its myarray field,
The syntax is Yote::ObjProvider::container_type( $o, 'myarray' ) <--- returns 'ARRAY';

=item count( container_id, args )

Returns the number of items in the given container. Args are optional and are

=over 4

=item search_fields - a list of fields to search for in collections of yote objects

=item search_terms - a list of terms to search for

=back

=item dirty( obj )

Marks the item as needing a save.

=item disconnect( )

Requests the data store used disconnect.

=item fetch( id )

Returns the array ref, hash ref or yote object specified by the numeric id or hash path.

=item first_id( id )

Returns the id of the first object in the system, the Root. This may or may not be 
numeric.

=item flush( id )

Removes any object with the given ID from any cache.

=item flush_all_volatile()

Clears out all caches.

=item get_id( obj )

Returns the id assigned to the array ref, hash ref or yote object. This method assigns that id
if none had been assigned to it.

=item hash_delete( hash_id, key )

Removes the key from the hash given by the id direclty from the database.

=item hash_fetch( hash_id, key )

Uses a database lookup to return the value for the key for the hash specified by hash_id.

=item hash_has_key( hash_id, key )

Uses a database lookup to return if the key for the hash specified by hash_id has a value.

=item hash_insert( hash_id, key, value )

Insert a key value pair directly into the database for the given hash_id.

=item list_delete( list_id, idx )

Uses the database to directly delete a given list element. This will cause the list to be reindexed.

=item list_fetch( list_id, idx )

Directly looks in the database to return the list element at the given index.

=item list_insert( list_id, val, idx )

Inserts the item into the list with an optional index. If not given, this inserts to the end of the list.
This method will cause the list to be reindexed.

=item package_methods( package_name )

This method returns a list of the public API methods attached to the given package name. This excludes the automatic getters and setters that are part of yote objects.


=item paginate( obj_id, args )

Returns a paginated list or hash that is attached to the object specified by obj_id. Arguments are 

=over 4

=item search_fields - a list of fields to search for in collections of yote objects

=item search_terms - a list of terms to search for

=item sort_fields - a list of fields to sort by for collections of yote objects

=item reversed_orders - a list of true or false values corresponding to the sort_fields list. A true value means that field is sorted in reverse

=item limit - maximum number of entries to return

=item skip - skip this many entries before returning the list

=item return_hash - return the result as a hashtable rather than as a list

=item reverse - return the result in reverse order

=back

=item recycle_objects( start_id, end_id )

Recycles all objects in the range given if they cannot trace back a path to root.

=item remove_from( list_id, item )

Removes the items ( by value ) from the list with the given id.

=item stow( obj )

This saves the hash ref, array ref or yote object argument in the data store.

=item stow_all( )

Stows all objects that are marked as dirty. This is called automatically by the application server and need not be explicitly called.

=item xform_in( value )

Returns the internal yote storage for the value, be it a string/number value, or yote reference.

=item xform_out( identifier )

Returns the external value given the internal identifier. The external value can be a string/number value or a yote reference.

=back

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
