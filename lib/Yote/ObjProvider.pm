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

# --------------------
#   PACKAGE METHODS
# --------------------
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

sub start_transaction {
    return $DATASTORE->start_transaction();
}

sub commit_transaction {
    return $DATASTORE->commit_transaction();
}

sub escape_for_xpath {
    my $str = shift;
    $str =~ s!/!\\/!g;
    return $str;
}

sub xpath {
    my $path = shift;
    return xform_out( $DATASTORE->xpath( $path ) );
}

sub xpath_count {
    my $path = shift;
    return $DATASTORE->xpath_count( $path );
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
# Inserts a value into the given xpath. /foo/bar/baz. Overwrites old value if it exists. Appends if it is a list.
#
sub xpath_list_insert {
    my $path = shift;
    my $item = shift;
    my $stow_val = ref( $item ) ? get_id( $item ) : "v$item";
    return $DATASTORE->xpath_list_insert( $path, $stow_val );
}

sub xpath_delete {
    my $path = shift;
    return $DATASTORE->xpath_delete( $path );
}

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
    my( $path, $paginate_start, $paginate_length ) = @_;
    my $list = $DATASTORE->paginate_xpath_list( $path, $paginate_start, $paginate_length );
    return [ map { xform_out( $_ ) } @$list ];
} #paginate_xpath_list

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
                _store_weak( $id_or_xpath, \@arry );
                return \@arry;
            }
            when('HASH') {
                my( %hash );
                tie %hash, 'Yote::Hash', $id_or_xpath, map { $_ => $data->{$_} } keys %$data;
                my $tied = tied %hash; $tied->[2] = \%hash;
                _store_weak( $id_or_xpath, \%hash );
                return \%hash;
            }
            default {
                eval("require $class");
		print STDERR Data::Dumper->Dump([$class,$!,$@]) if $@;
                my $obj = $class->new( $id_or_xpath );
                $obj->{DATA} = $data;
                $obj->{ID} = $id_or_xpath;
                _store_weak( $id_or_xpath, $obj );
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
                _store_weak( $tied->[0], $ref );
                return $tied->[0];
            }
            my( @data ) = @$ref;
            my $id = $DATASTORE->get_id( $class );
            tie @$ref, 'Yote::Array', $id;
            my $tied = tied @$ref; $tied->[2] = $ref;
            push( @$ref, @data );
            dirty( $ref, $id );
            _store_weak( $id, $ref );
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
                _store_weak( $tied->[0], $ref );
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
            _store_weak( $id, $ref );
            return $id;
        }
        default {
            $ref->{ID} ||= $DATASTORE->get_id( $class );
            _store_weak( $ref->{ID}, $ref );
            return $ref->{ID};
        }
    }
} #get_id

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

sub a_child_of_b {
    my( $a, $b, $seen ) = @_;
    my $bref = ref( $b );
    return 0 unless $bref && ref($a);
    $seen ||= {};
    my $bid = get_id( $b );
    return 0 if $seen->{$bid};
    $seen->{$bid} = 1;
    return 1 if get_id($a) == get_id($b);
    given( $bref ) {
        when(/^(ARRAY|Yote::Array)$/) {
            for my $obj (@$b) {
                return 1 if( a_child_of_b( $a, $obj, $seen ) );
            }
        }
        when(/^(HASH|Yote::Hash)$/) {
            for my $obj (values %$b) {
                return 1 if( a_child_of_b( $a, $obj, $seen ) );
            }
        }
        default {
            for my $obj (values %{$b->{DATA}}) {
                return 1 if( a_child_of_b( $a, xform_out( $obj ), $seen ) );
            }
        }
    }
    return 0;
} #a_child_of_b

sub apply_udpates {
    my $updates = shift;

    $DATASTORE->apply_updates( $updates );

} #apply_updates

sub stow_all {
    my( %objs ) = %{$Yote::ObjProvider::DIRTY};
    for my $id (keys  %{$Yote::ObjProvider::WEAK_REFS} ) {
	$objs{ $id } = $Yote::ObjProvider::WEAK_REFS->{$id};
    }
    for my $obj (values %objs) {
        stow( $obj );
    }
} #stow_all

sub stow {
    my( $obj ) = @_;
    my $class = ref( $obj );
    return unless $class;
    my $id = get_id( $obj );
    die unless $id;
    my $data = _raw_data( $obj );
    given( $class ) {
        when('ARRAY') {
            $DATASTORE->stow( $id,'ARRAY', $data );
            _clean( $id );
        }
        when('HASH') {
            $DATASTORE->stow( $id,'HASH',$data );
            _clean( $id );
        }
        when('Yote::Array') {
            if( _is_dirty( $id ) ) {
                $DATASTORE->stow( $id,'ARRAY',$data );
                _clean( $id );
            }
            for my $child (@$data) {
                if( $child > 0 && $Yote::ObjProvider::DIRTY->{$child} ) {
                    stow( $Yote::ObjProvider::DIRTY->{$child} );
                }
            }
        }
        when('Yote::Hash') {
            if( _is_dirty( $id ) ) {
                $DATASTORE->stow( $id, 'HASH', $data );
            }
            _clean( $id );
            for my $child (values %$data) {
                if( $child > 0 && $Yote::ObjProvider::DIRTY->{$child} ) {
                    stow( $Yote::ObjProvider::DIRTY->{$child} );
                }
            }
        }
        default {
            if( _is_dirty( $id ) ) {
                $DATASTORE->stow( $id, $class, $data );
                _clean( $id );
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

sub stow_updates {
    my( $obj ) = @_;
    my( @cmds );
    my $class = ref( $obj );
    return unless $class;
    my $id = get_id( $obj );
    die unless $id;
    my $data = _raw_data( $obj );
    given( $class ) {
        when('ARRAY') {
            push( @cmds, @{$DATASTORE->stow_updates( $id,'ARRAY', $data )} );
            _clean( $id );
        }
        when('HASH') {
            push( @cmds, @{$DATASTORE->stow_updates( $id,'HASH',$data )} );
            _clean( $id );
        }
        when('Yote::Array') {
            if( _is_dirty( $id ) ) {
                push( @cmds, @{$DATASTORE->stow_updates( $id,'ARRAY',$data )} );
                _clean( $id );
            }
            for my $child (@$data) {
                if( $child > 0 && $Yote::ObjProvider::DIRTY->{$child} ) {
                    push( @cmds, @{stow_updates( $Yote::ObjProvider::DIRTY->{$child} )} );
                }
            }
        }
        when('Yote::Hash') {
            if( _is_dirty( $id ) ) {
                push( @cmds, @{$DATASTORE->stow_updates( $id, 'HASH', $data )} );
            }
            _clean( $id );
            for my $child (values %$data) {
                if( $child > 0 && $Yote::ObjProvider::DIRTY->{$child} ) {
                    push( @cmds, @{stow_updates( $Yote::ObjProvider::DIRTY->{$child} )} );
                }
            }
        }
        default {
            if( _is_dirty( $id ) ) {
                push( @cmds, @{$DATASTORE->stow_updates( $id, $class, $data )} );
                _clean( $id );
            }
            for my $val (values %$data) {
                if( $val > 0 && $Yote::ObjProvider::DIRTY->{$val} ) {
                    push( @cmds, @{stow_updates( $Yote::ObjProvider::DIRTY->{$val} )} );
                }
            }
        }
    } #given
    return \@cmds;
} #stow

sub xform_out {
    my $val = shift;
    return undef unless defined( $val );
    if( index($val,'v') == 0 ) {
        return substr( $val, 1 );
    }
    return fetch( $val );
}

sub xform_in {
    my $val = shift;
    if( ref( $val ) ) {
        return get_id( $val );
    }
    return "v$val";
}

sub reset_changed {
    $Yote::ObjProvider::CHANGED = {};
}

sub fetch_changed {
    return [keys %{$Yote::ObjProvider::CHANGED}];
}

#
# Markes given object as dirty.
#
sub dirty {
    my $obj = shift;
    my $id = shift;
    $Yote::ObjProvider::DIRTY->{$id} = $obj;
    $Yote::ObjProvider::CHANGED->{$id} = $obj;
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

sub max_id {
    my $self = shift;
    return $DATASTORE->max_id();
}

#
# Returns true if object connects to root
#
sub has_path_to_root {
    my( $self, $obj_id ) = @_;
    return $DATASTORE->has_path_to_root( $obj_id );
} #has_path_to_root

sub path_to_root {
    my( $obj ) = @_;
    return $DATASTORE->path_to_root( get_id($obj) );
} #path_to_root

# returns the app that the given object belongs to, if any
sub app_for_object {
    my $obj = shift;
    my( @xpath ) = split( /\//, Yote::ObjProvider::path_to_root( $obj ) );
    if( @xpath == 2 ) {
	return $obj; # this is the app itself
    }
    if( @xpath > 3 ) {
	return Yote::ObjProvider::xpath( join( '/', @xpath[0..2] ) );
    }
    
} #_get_my_app


sub recycle_object {
    my( $self, $obj_id ) = @_;
    return $DATASTORE->recycle_object( $obj_id );
}


    

#
# 'private' methods ----------------------
#

#
# Returns data structure representing object. References are integers. Values start with 'v'.
#
sub _raw_data {
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
} #_raw_data

sub _store_weak {
    my( $id, $ref ) = @_;
    my $weak = $ref;
    weaken( $weak );
    $Yote::ObjProvider::WEAK_REFS->{$id} = $weak;
} #_store_weak

sub _is_dirty {
    my $obj = shift;
    my $id = ref($obj) ? get_id($obj) : $obj;
    return $Yote::ObjProvider::DIRTY->{$id};
} #_is_dirty

sub _clean {
    my $id = shift;
    delete $Yote::ObjProvider::DIRTY->{$id};
} #_clean

1;
__END__

=head1 NAME

Yote::ObjProvider - Serves Yote objects. Configured to a persistance engine.

=head1 DESCRIPTION

This module is the front end for assigning IDs to objects, fetching objects, keeping track of objects that need saving (are dirty) and saving all dirty objects.

The public methods of interest are 

=over 4

=item fetch

Returns an object given an id.

my $object = Yote::ObjProvider::fetch( $object_id );

=item xpath

Given a path designator, returns the object at the end of it, starting in the root. The notation is /foo/bar/baz where foo, bar and baz are field names. 

For example, get the value of the hash keyed to 'zap' where the hash is the  second element of an array that is attached to the root with the key 'baz' : 

my $object = Yote::ObjProvider::xpath( "/baz/1/zap" );


=item xpath_count

Given a path designator, returns the number of fields of the object at the end of it, starting in the root. The notation is /foo/bar/baz where foo, bar and baz are field names. This is useful for counting how many things are in a list.

my $count = Yote::ObjProvider::xpath_count( "/foo/bar/baz/myarray" );

=item a_child_of_b 

Takes two objects as arguments. Returns true if object a is branched off of object b.

if(  Yote::ObjProvider::xpath_count( $obj_a, $obj_b ) ) {


=item stow_all

Stows all objects that are marked as dirty. This is called automatically by the application server and need not be explicitly called.

Yote::ObjProvider::stow_all;

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
