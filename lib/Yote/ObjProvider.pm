package Yote::ObjProvider;

use strict;

use feature ':5.10';

use Yote::Array;
use Yote::Hash;
use Yote::Obj;
use Yote::YoteRoot;
use Yote::SQLiteIO;

use Crypt::Passwd;
use WeakRef;

$Yote::ObjProvider::DIRTY = {};
$Yote::ObjProvider::CHANGED = {};
$Yote::ObjProvider::PKG_TO_METHODS = {};
$Yote::ObjProvider::WEAK_REFS = {};
$Yote::ObjProvider::LOGIN_OBJECTS = {};
$Yote::ObjProvider::GUEST_TOKEN_OBJECTS = {};

our $DATASTORE;

use vars qw($VERSION);

$VERSION = '0.01';


# ------------------------------------------------------------------------------------------
#      * INIT METHODS *
# ------------------------------------------------------------------------------------------
sub new {
    my $ref = shift;
    my $class = ref( $ref ) || $ref;
    return bless {}, $class;
}

sub init {
    my $args = ref( $_[0] ) ? $_[0] : { @_ };
    $DATASTORE = new Yote::SQLiteIO( $args );
    $DATASTORE->ensure_datastore();
    fetch(1) || new Yote::YoteRoot(); #ensure that there is the singleton root object.
} #init


# ------------------------------------------------------------------------------------------
#      * PUBLIC CLASS METHODS *
# ------------------------------------------------------------------------------------------

sub commit_transaction {
    return $DATASTORE->commit_transaction();
}

#
# Markes given object as dirty.
#
sub dirty {
    my $obj = shift;
    my $id = shift;
    $Yote::ObjProvider::DIRTY->{$id} = $obj;
    $Yote::ObjProvider::CHANGED->{$id} = $obj;
} #dirty


sub disconnect {
    return $DATASTORE->disconnect();
}

#
# Encrypt the password so its not saved in plain text.
#
sub encrypt_pass {
    my( $pw, $acct ) = @_;
    return $acct ? unix_std_crypt( $pw, $acct->get_handle() ) : undef;
} #encrypt_pass

sub fetch {
    my( $id_or_xpath ) = @_;

    if( $id_or_xpath && $id_or_xpath == 0 ) {
	#assume xpath
	return xpath( $id_or_xpath );
    }

    #
    # Return the object if we have a reference to its dirty state.
    #
    my $ref = $Yote::ObjProvider::DIRTY->{$id_or_xpath} || $Yote::ObjProvider::WEAK_REFS->{$id_or_xpath};
    return $ref if $ref;

    my $obj_arry = $DATASTORE->fetch( $id_or_xpath );

    if( $obj_arry ) {
        my( $id_or_xpath, $class, $data ) = @$obj_arry;
        given( $class ) {
            when('ARRAY') {
                my( @arry );
                tie @arry, 'Yote::Array', $id_or_xpath, @$data;
                my $tied = tied @arry; $tied->[2] = \@arry;
                __store_weak( $id_or_xpath, \@arry );
                return \@arry;
            }
            when('HASH') {
                my( %hash );
                tie %hash, 'Yote::Hash', $id_or_xpath, map { $_ => $data->{$_} } keys %$data;
                my $tied = tied %hash; $tied->[2] = \%hash;
                __store_weak( $id_or_xpath, \%hash );
                return \%hash;
            }
            default {
                eval("require $class");
		print STDERR Data::Dumper->Dump([$class,$!,$@]) if $@;
                my $obj = $class->new( $id_or_xpath );
                $obj->{DATA} = $data;
                $obj->{ID} = $id_or_xpath;
                __store_weak( $id_or_xpath, $obj );
                return $obj;
            }
        }
    }
    return undef;
} #fetch


sub get_id {
    my $ref = shift;
    my $class = ref( $ref );
    given( $class ) {
        when('Yote::Array') {
            return $ref->[0];
        }
        when('ARRAY') {
            my $tied = tied @$ref;
            if( $tied ) {
                $tied->[0] ||= $DATASTORE->get_id( "ARRAY" );
                __store_weak( $tied->[0], $ref );
                return $tied->[0];
            }
            my( @data ) = @$ref;
            my $id = $DATASTORE->get_id( $class );
            tie @$ref, 'Yote::Array', $id;
            my $tied = tied @$ref; $tied->[2] = $ref;
            push( @$ref, @data );
            dirty( $ref, $id );
            __store_weak( $id, $ref );
            return $id;
        }
        when('Yote::Hash') {
            my $wref = $ref;
            return $ref->[0];
        }
        when('HASH') {
            my $tied = tied %$ref;

            if( $tied ) {
                $tied->[0] ||= $DATASTORE->get_id( "HASH" );
                __store_weak( $tied->[0], $ref );
                return $tied->[0];
            }
            my $id = $DATASTORE->get_id( $class );
            my( %vals ) = %$ref;
            tie %$ref, 'Yote::Hash', $id;
            my $tied = tied %$ref; $tied->[2] = $ref;
            for my $key (keys %vals) {
                $ref->{$key} = $vals{$key};
            }
            dirty( $ref, $id );
            __store_weak( $id, $ref );
            return $id;
        }
        default {
            $ref->{ID} ||= $DATASTORE->get_id( $class );
            __store_weak( $ref->{ID}, $ref );
            return $ref->{ID};
        }
    }
} #get_id

#
# Returns true if object connects to root
#
sub has_path_to_root {
    my( $self, $obj_id ) = @_;
    return $DATASTORE->has_path_to_root( $obj_id );
} #has_path_to_root


sub max_id {
    my $self = shift;
    return $DATASTORE->max_id();
}

sub package_methods {
    my $pkg = shift;
    my $methods = $Yote::ObjProvider::PKG_TO_METHODS{$pkg};
    unless( $methods ) {

        no strict 'refs';
	my @m = grep { $_ && $_ !~ /^(_.*|AUTOLOAD|BEGIN|DESTROY|CLONE_SKIP|ISA|VERSION|unix_std_crypt|is|add_to_.*|remove_from_.*|import|[sg]et_.*|can|isa|new|decode_base64|encode_base64)$/ } grep { $_ !~ /::/ } keys %{"${pkg}\::"};

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

#
# Returns a hash of paginated items that belong to the xpath.
#
sub paginate_xpath {
    my( $path, $paginate_start, $paginate_length ) = @_;
    my $hash = $DATASTORE->paginate_xpath( $path, $paginate_start, $paginate_length );
    return { map { $_ => xform_out( $hash->{$_} ) } keys %$hash };
} #paginate_xpath

#
# Returns a hash of paginated items that belong to the xpath. Note that this 
# does not preserve indexes ( for example, if the list has two rows, and first index in the database is 3, the list returned is still [ 'val1', 'val2' ]
#   rather than [ undef, undef, undef, 'val1', 'val2' ]
#
sub paginate_xpath_list {
    my( $path, $paginate_length, $paginate_start ) = @_;
    my $list = $DATASTORE->paginate_xpath_list( $path, $paginate_length, $paginate_start );
    return [ map { xform_out( $_ ) } @$list ];
} #paginate_xpath_list

sub path_to_root {
    my( $obj ) = @_;
    return $DATASTORE->path_to_root( get_id($obj) );
} #path_to_root

#
# Deep clone this object. This will clone any yote object that is not an AppRoot.
#
sub power_clone {
    my( $item, $replacements ) = @_;
    my $class = ref( $item );
    return $item unless $class;

    my $at_start = 0;
    unless( $replacements ) {
        $at_start = 1;
        $replacements ||= {};
    }
    my $id = get_id( $item );
    return $replacements->{$id} if $replacements->{$id};

    if( $class eq 'ARRAY' ) {
        my $arry_clone = [ map { power_clone( $_, $replacements ) } @$item ];
        my $c_id = get_id( $arry_clone );
        $replacements->{$id} = $c_id;
        return $arry_clone;
    }
    elsif( $class eq 'HASH' ) {
        my $hash_clone = { map { $_ => power_clone( $item->{$_}, $replacements ) } keys %$item };
        my $c_id = get_id( $hash_clone );
        $replacements->{$id} = $c_id;
        return $hash_clone;
    }
    else {
        return $item if $item->isa( 'Yote::AppRoot' ) && (! $at_start);
    }

    my $clone = $class->new;
    $replacements->{ $id } = get_id( $clone );

    for my $field (keys %{$item->{DATA}}) {
        my $id_or_val = $item->{DATA}{$field};
        if( $id_or_val > 0 ) { #means its a reference
            $clone->{DATA}{$field} = $replacements->{$id_or_val} || xform_in( power_clone( xform_out( $id_or_val ), $replacements ) );
        } else {
            $clone->{DATA}{$field} = $id_or_val;
        }
    }

    if( $at_start ) {
	my( @cloned ) = map { fetch($_)  } keys %$replacements;
	my( %cloned );
	for my $obj (@cloned) {
	    $cloned{ ref( $obj ) }++;
	}
    }

    return $clone;
    
} #power_clone


sub recycle_object {
    my( $self, $obj_id ) = @_;
    return $DATASTORE->recycle_object( $obj_id );
}

#
# Finds objects not connected to the root and recycles them.
#
sub recycle_objects {
    my( $self, $start_id, $end_id ) = @_;
    $start_id ||= 2;
    $end_id   ||= $self->max_id();

    my $recycled;
    
    for( my $id=$start_id; $id <= $end_id; $id++ ) {
	my $obj = fetch( $id );
	if( $obj && ( ! $self->has_path_to_root( $id ) ) ) {
	    $self->recycle_object( $id );
	    ++$recycled;
	}
    }
    #print STDERR "RECYCLED $recycled objects\n";
    return $recycled;
} #recycle_objects

sub reset_changed {
    $Yote::ObjProvider::CHANGED = {};
}
sub start_transaction {
    return $DATASTORE->start_transaction();
}
sub stow {
    my( $obj ) = @_;
    my $class = ref( $obj );
    return unless $class;
    my $id = get_id( $obj );
    die unless $id;
    my $data = __raw_data( $obj );
    given( $class ) {
        when('ARRAY') {
            $DATASTORE->stow( $id,'ARRAY', $data );
            __clean( $id );
        }
        when('HASH') {
            $DATASTORE->stow( $id,'HASH',$data );
            __clean( $id );
        }
        when('Yote::Array') {
            if( __is_dirty( $id ) ) {
                $DATASTORE->stow( $id,'ARRAY',$data );
                __clean( $id );
            }
            for my $child (@$data) {
                if( $child > 0 && $Yote::ObjProvider::DIRTY->{$child} ) {
                    stow( $Yote::ObjProvider::DIRTY->{$child} );
                }
            }
        }
        when('Yote::Hash') {
            if( __is_dirty( $id ) ) {
                $DATASTORE->stow( $id, 'HASH', $data );
            }
            __clean( $id );
            for my $child (values %$data) {
                if( $child > 0 && $Yote::ObjProvider::DIRTY->{$child} ) {
                    stow( $Yote::ObjProvider::DIRTY->{$child} );
                }
            }
        }
        default {
            if( __is_dirty( $id ) ) {
                $DATASTORE->stow( $id, $class, $data );
                __clean( $id );
            }
            for my $val (values %$data) {
                if( $val > 0 && $Yote::ObjProvider::DIRTY->{$val} ) {
                    stow( $Yote::ObjProvider::DIRTY->{$val} );
                }
            }
        }
    } #given
    delete $Yote::ObjProvider::WEAK_REFS->{$id};
    
} #stow

sub stow_all {
    my( %objs ) = %{$Yote::ObjProvider::DIRTY};
    for my $id (keys  %{$Yote::ObjProvider::WEAK_REFS} ) {
	$objs{ $id } = $Yote::ObjProvider::WEAK_REFS->{$id};
    }
    for my $obj (values %objs) {
        stow( $obj );
    }
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

sub xpath {
    my $path = shift;
    return xform_out( $DATASTORE->xpath( $path ) );
}

sub xpath_count {
    my $path = shift;
    return $DATASTORE->xpath_count( $path );
}

sub xpath_delete {
    my $path = shift;
    return $DATASTORE->xpath_delete( $path );
}

#
# Inserts a value into the given xpath. /foo/bar/baz. Overwrites old value if it exists. Appends if it is a list.
#
sub xpath_insert {
    my $path = shift;
    my $item = shift;
    my $stow_val = ref( $item ) ? get_id( $item ) : "v$item";
    return $DATASTORE->xpath_insert( $path, $stow_val );
}

#
# Appends a value into the list located at the given xpath.
#
sub xpath_list_insert {
    my $path = shift;
    my $item = shift;
    my $stow_val = ref( $item ) ? get_id( $item ) : "v$item";
    return $DATASTORE->xpath_list_insert( $path, $stow_val );
}

# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

sub __clean {
    my $id = shift;
    delete $Yote::ObjProvider::DIRTY->{$id};
} #__clean

sub __fetch_changed {
    return [keys %{$Yote::ObjProvider::CHANGED}];
}

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
    given( $class ) {
        when('ARRAY') {
            my $tied = tied @$obj;
            if( $tied ) {
                return $tied->[1];
            } else {
                die;
            }
        }
        when('HASH') {
            my $tied = tied %$obj;
            if( $tied ) {
                return $tied->[1];
            } else {
                die;
            }
        }
        when('Yote::Array') {
            return $obj->[1];
        }
        when('Yote::Hash') {
            return $obj->[1];
        }
        default {
            return $obj->{DATA};
        }
    }
} #__raw_data

sub __store_weak {
    my( $id, $ref ) = @_;
    my $weak = $ref;
    weaken( $weak );
    $Yote::ObjProvider::WEAK_REFS->{$id} = $weak;
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

=item commit_transaction( )

Requests the data store used commit the transaction.

=item dirty( obj )

Marks the object as dirty

=item disconnect( )

Requests the data store used disconnect.

=item encrypt_pass( pass_string )

Returns a string of the argument encrypted.

=item fetch( id_or_xpath )

Returns the array ref, hash ref or yote object specified by the numeric id or hash path.

=item get_id( obj )

Returns the id assigned to the array ref, hash ref or yote object. This method assigns that id 
if none had been assigned to it.

=item has_path_to_root( obj )

Returns true if the argument ( which can be an array ref, hash ref or yote object ) can
trace a path back to the root Yote::YoteRoot object ( id 1 ). This is used to detect if the
object is dead and should be recycled.

=item max_id( )

Returns the max id of all objects in the data store. This is used by test programs.

=item package_methods( package_name )

This method returns a list of the public API methods attached to the given package name. This excludes the automatic getters and setters that are part of yote objects.

=item paginate_xpath( xpath, start, length )

This method returns a paginated portion of a list that is attached to the xpath given.

=item path_to_root( object )

Returns the xpath of the given object tracing back a path to the root. This is not guaranteed to be the shortest path to root.

=item power_clone( item )

Returns a deep clone of the object. This will clone any object that is part of the yote system except for the yote root or any app (a Yote::AppRoot object)

=item recycle_object( obj_id )

Sets the available for recycle mark on the object entry in the database by object id and removes its data.

=item recycle_objects( start_id, end_id )

Recycles all objects in the range given if they cannot trace back a path to root.

=item reset_changed( )

This is a helper method that clears out a changed hash. The hash stores objects that become dirty until reset changed is called again.

=item start_transaction( )

Requests that the underlying data store start a transaction.

=item stow( obj )

This saves the hash ref, array ref or yote object argument in the data store.

=item stow_all( )

Stows all objects that are marked as dirty. This is called automatically by the application server and need not be explicitly called.

=item xform_in( value )

Returns the internal yote storage for the value, be it a string/number value, or yote reference.

=item xform_out( identifier )

Returns the external value given the internal identifier. The external value can be a string/number value or a yote reference.

=item xpath( path )

Given a path designator, returns the object at the end of it, starting in the root. The notation is /foo/bar/baz where foo, bar and baz are field names. 

For example, get the value of the hash keyed to 'zap' where the hash is the  second element of an array that is attached to the root with the key 'baz' : 

my $object = Yote::ObjProvider::xpath( "/baz/1/zap" );

=item xpath_count( path )

Given a path designator, returns the number of fields of the object at the end of it, starting in the root. The notation is /foo/bar/baz where foo, bar and baz are field names. This is useful for counting how many things are in a list.

my $count = Yote::ObjProvider::xpath_count( "/foo/bar/baz/myarray" );

Takes two objects as arguments. Returns true if object a is branched off of object b.

if(  Yote::ObjProvider::xpath_count( $obj_a, $obj_b ) ) {

=item xpath_delete( path )

Deletes the entry specified by the path.

=item xpath_insert( path, item )

Inserts the item at the given xpath, overwriting anything that had existed previously.

=item xpath_list_insert( path, item )

Appends the item to the list located at the given xpath.

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
