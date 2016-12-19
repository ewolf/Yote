package Yote;

use strict;
use warnings;
no  warnings 'uninitialized';

use vars qw($VERSION);

$VERSION = '1.45';

=head1 NAME

Yote - Persistant Perl container objects in a directed graph of lazilly loaded nodes.

=head1 DESCRIPTION

This is for anyone who wants to store arbitrary structured state data and doesn't have
the time or inclination to write a schema or configure some framework. This can be used
orthagonally to any other storage system.

Yote only loads data as it needs too. It does not load all stored containers at once.
Data is stored in a data directory and is stored using the Data::RecordStore module. A Yote
container is a key/value store where the values can be strings, numbers, arrays, hashes
or other Yote containers.

The entry point for all Yote data stores is the root node. All objects in the store are
unreachable if they cannot trace a reference path back to this node. If they cannot, running
compress_store will remove them.

There are lots of potential uses for Yote, and a few come to mind :

 * configuration data
 * data modeling
 * user preference data
 * user account data
 * game data
 * shopping carts
 * product information

=head1 SYNOPSIS

 use Yote;

 my $store = Yote::open_store( '/path/to/data-directory' );

 my $root_node = $store->fetch_root;

 $root_node->add_to_myList( $store->newobj( {
    someval  => 123.53,
    somehash => { A => 1 },
    someobj  => $store->newobj( { foo => "Bar" },
                'Optional-Yote-Subclass-Package' );
 } );

 # the root node now has a list 'myList' attached to it with the single
 # value of a yote object that yote object has two fields,
 # one of which is an other yote object.

 $root_node->add_to_myList( 42 );

 #
 # New Yote container objects are created with $store->newobj. Note that
 # they must find a reference path to the root to be protected from
 # being deleted from the record store upon compression.
 #
 my $newObj = $store->newobj;

 $root_node->set_field( "Value" );

 my $val = $root_node->get_value( "default" );
 # $val eq 'default'

 $val = $root_node->get_value( "Somethign Else" );
 # $val eq 'default' (old value not overridden by a new default value)


 my $otherval = $root_node->get( 'ot3rv@l', 'other default' );
 # $otherval eq 'other default'

 $root_node->set( 'ot3rv@l', 'newy valuye' );
 $otherval2 = $root_node->get( 'ot3rv@l', 'yet other default' );
 # $otherval2 eq 'newy valuye'

 $root_node->set_value( "Something Else" );

 my $val = $root_node->get_value( "default" );
 # $val eq 'Something Else'

 my $myList = $root_node->get_myList;

 for my $example (@$myList) {
    print ">$example\n";
 }

 #
 # Each object gets a unique ID which can be used to fetch that
 # object directly from the store.
 #
 my $someid = $root_node->get_someobj->{ID};

 my $someref = $store->fetch( $someid );

 #
 # Even hashes and array have unique yote IDS. These can be
 # determined by calling the _get_id method of the store.
 #
 my $hash = $root_node->set_ahash( { zoo => "Zar" } );
 my $hash_id = $store->_get_id( $hash );
 my $other_ref_to_hash = $store->fetch( $hash_id );

 #
 # Anything that cannot trace a reference path to the root
 # is eligable for being removed upon compression. 
 #

=head1 PUBLIC METHODS

=cut


=head2 open_store( '/path/to/directory' )

Starts up a persistance engine and returns it.

=cut

sub open_store {
    my $path = pop;
    my $store = Yote::ObjStore->_new( { store => $path } );
    $store->_init;
    $store;
}

# ---------------------------------------------------------------------------------------------------------------------

package Yote::ObjStore;

use strict;
use warnings;
no warnings 'numeric';
no warnings 'uninitialized';
no warnings 'recursion';

use Devel::Refcount 'refcount';
use File::Copy;
use WeakRef;
use Module::Loaded;

=head1 NAME

 Yote::ObjStore - manages Yote::Obj objects in a graph.

=head1 DESCRIPTION

The Yote::ObjStore does the following things :

 * fetches the root object
 * creates new objects
 * fetches existing objects by id
 * saves all new or changed objects
 * finds objects that cannot connect to the root node and removes them

=cut

# ------------------------------------------------------------------------------------------
#      * PUBLIC CLASS METHODS *
# ------------------------------------------------------------------------------------------

=head2 fetch_root

 Returns the root node of the graph. All things that can be
trace a reference path back to the root node are considered active
and are not removed when the object store is compressed.

=cut
sub fetch_root {
    my $self = shift;
    die "fetch_root must be called on Yote store object" unless ref( $self );
    my $root = $self->fetch( $self->_first_id );
    unless( $root ) {
        $root = $self->_newroot;
        $root->{ID} = $self->_first_id;
        $self->_stow( $root );
    }
    $root;
} #fetch_root

=head2 newobj( { ... data .... }, optionalClass )

 Creates a container object initialized with the
 incoming hash ref data. The class of the object must be either
 Yote::Obj or a subclass of it. Yote::Obj is the default.

 Once created, the object will be saved in the data store when
 $store->stow_all has been called.  If the object is not attached
 to the root or an object that can be reached by the root, it will be
 remove when Yote::ObjStore::Compress is called.

=cut
sub newobj {
    my( $self, $data, $class ) = @_;
    $class ||= 'Yote::Obj';
    $class->_new( $self, $data );
}

sub _newroot {
    my $self = shift;
    Yote::Obj->_new( $self, {}, $self->_first_id );
}


=head2 fetch( $id )

 Returns the object with the given id.

=cut
sub fetch {
    my( $self, $id ) = @_;
    return undef unless $id;
    #
    # Return the object if we have a reference to its dirty state.
    #
    my $ref = $self->{_DIRTY}{$id} || $self->{_WEAK_REFS}{$id};
    if( defined $ref ) {
        return $ref;
    }
    my $obj_arry = $self->{_DATASTORE}->_fetch( $id );

    if( $obj_arry ) {
        my( $id, $class, $data ) = @$obj_arry;
        if( $class eq 'ARRAY' ) {
            my( @arry );
            tie @arry, 'Yote::Array', $self, $id, @$data;
            my $tied = tied @arry; $tied->[3] = \@arry;
            $self->_store_weak( $id, \@arry );
            return \@arry;
        }
        elsif( $class eq 'HASH' ) {
            my( %hash );
            tie %hash, 'Yote::Hash', $self, $id, map { $_ => $data->{$_} } keys %$data;
            my $tied = tied %hash; $tied->[3] = \%hash;
            $self->_store_weak( $id, \%hash );
            return \%hash;
        }
        else {
            my $obj;
            eval {
                my $path = $class;
                unless( $INC{ $class } ) {
                    eval("use $class");
                }
                $obj = $self->{_WEAK_REFS}{$id} || $class->_instantiate( $id, $self );
            };
            die $@ if $@;
            $obj->{DATA} = $data;
            $obj->{ID} = $id;
            $self->_store_weak( $id, $obj );
            $obj->_load();
            return $obj;
        }
    }
    return undef;
} #fetch

=head2 run_recycler

=cut
sub run_recycler {
    my $self = shift;
     $self->stow_all();
    $self->{_DATASTORE}->_recycle_objects();
} #run_recycler

=head2 compress_store

This creates a new data store with all objects
removed that cannot be traced back to the root.

This will fail if the following directories 
exist :
  ${ROOT-DIRECOTRY-FOR-OBJECT-STORE}_COMPRESS_BAK
  ${ROOT-DIRECOTRY-FOR-OBJECT-STORE}_NEW_RECYC

The first directory is where the original object
store gets backed up after the compression. If 
the compression is a success, it should be removed.

The second is a temporary working directory for the
new copied over database.

This requires enough room on the file system
to potentially double the size of the database
temporarily as it is copied to a new one.

=cut
sub compress_store {
    my( $self, $newdir, $backdir ) = @_;
    $self->stow_all();

    my $original_dir = $self->{args}{store};
    $backdir //= $original_dir . '_COMPRESS_BAK';
    $newdir  //= $original_dir . '_NEW_RECYC';

    if( -x $backdir ) {
        die "Unable to run compress store, backup directory '$backdir' already exists.";
    }

    if( -x $newdir ) {
        die "Unable to run compress store, temp directory '$newdir' already exists.";
    }

    if( $self->_has_weak_refs ) {
        die "Unable to run compress store. There are still outstanding references to yote objects that would be deleted during the compress.";
    }
    my $newstore = Yote::ObjStore->_new( { store => $newdir } );

    my( @copy_ids ) = ( $self->_first_id );

    my $count = 0;
    my( %seen );
    while( @copy_ids ) {
        my $id = shift @copy_ids;
#        next if $seen{$id}++;
        next if $newstore->{_DATASTORE}{DATA_STORE}->has_id( $id ) && $id != $self->_first_id;
        next if$id == $self->_first_id && $count > 0;
        
        print STDERR "\t$id";
        if( ++$count > 80 ) {
            print STDERR "\n";
            $count = 0;
        }
        
        my $obj = $self->fetch( $id );
#        $obj->{STORE} = $newstore;

        $newstore->{_DATASTORE}{DATA_STORE}->ensure_entry_count( $id - 1 );
        $newstore->_dirty( $obj, $id );
        $newstore->_stow( $obj, $id );

        my $r = ref( $obj );
        if ( $r eq 'ARRAY' ) {
            my $tied = tied @$obj;
            push @copy_ids, grep { $_ > 0 } @{$tied->[1]};
        } elsif ( $r eq 'HASH' ) {
            my $tied = tied %$obj;
            push @copy_ids, grep { $_ > 0 } values %{$tied->[1]};
        } else {
            push @copy_ids, grep { $_ > 0 } values %{$obj->{DATA}};
        }
    }
    
    move( $original_dir, $backdir ) or die $!;
    move( $newdir, $original_dir ) or die $!;

} #compress_store
=head2 stow_all

 Saves all newly created or dirty objects.

=cut
sub stow_all {
    my $self = $_[0];
    my @odata;
    for my $obj (values %{$self->{_DIRTY}} ) {
        my $cls;
        my $ref = ref( $obj );
        if( $ref eq 'ARRAY' || $ref eq 'Yote::Array' ) {
            $cls = 'ARRAY';
        } elsif( $ref eq 'HASH' || $ref eq 'Yote::Hash' ) {
            $cls = 'HASH';
        } else {
            $cls = $ref;
        }
        push( @odata, [ $self->_get_id( $obj ), $cls, $self->_raw_data( $obj ) ] );
    }
    $self->{_DATASTORE}->_stow_all( \@odata );
    $self->{_DIRTY} = {};
} #stow_all


# -------------------------------
#      * PRIVATE METHODS *
# -------------------------------
sub _new { #Yote::ObjStore
    my( $pkg, $args ) = @_;
    my $self = bless {
        _DIRTY     => {},
        _WEAK_REFS => {},
        args       => $args,
    }, $pkg;
    $self->{_DATASTORE} = Yote::YoteDB->open( $self, $args );
    $self;
} #_new

sub _init {
    my $self = shift;
    for my $pkg ( qw( Yote::Obj Yote::Array Yote::Hash ) ) {
        $INC{ $pkg } or eval("use $pkg");
    }
    $self->fetch_root;
    $self->stow_all;
    $self;
}


#
# Markes given object as dirty.
#
sub _dirty {
    # ( $self, $ref, $id
    $_[0]->{_DIRTY}->{$_[2]} = $_[1];
} #_dirty

#
# Returns the first ID that is associated with the root Root object
#
sub _first_id {
    shift->{_DATASTORE}->_first_id();
} #_first_id

sub _get_id {
    shift->__get_id( shift );
}

sub __get_id {
    my( $self, $ref ) = @_;

    my $class = ref( $ref );
    die "__get_id requires reference. got '$ref'" unless $class;
    
    if( $class eq 'Yote::Array') {
        return $ref->[0];
    }
    elsif( $class eq 'ARRAY' ) {
        my $tied = tied @$ref;
        if( $tied ) {
            $tied->[0] ||= $self->{_DATASTORE}->_get_id( "ARRAY" );
            return $tied->[0];
        }
        my( @data ) = @$ref;
        my $id = $self->{_DATASTORE}->_get_id( $class );
        tie @$ref, 'Yote::Array', $self, $id;
        $tied = tied @$ref; $tied->[3] = $ref;
        push( @$ref, @data );
        $self->_dirty( $ref, $id );
        $self->_store_weak( $id, $ref );
        return $id;
    }
    elsif( $class eq 'Yote::Hash' ) {
        my $wref = $ref;
        return $ref->[0];
    }
    elsif( $class eq 'HASH' ) {
        my $tied = tied %$ref;
        if( $tied ) {
            $tied->[0] ||= $self->{_DATASTORE}->_get_id( "HASH" );
            return $tied->[0];
        }
        my $id = $self->{_DATASTORE}->_get_id( $class );

        my( %vals ) = %$ref;
        tie %$ref, 'Yote::Hash', $self, $id;
        $tied = tied %$ref; $tied->[3] = $ref;
        for my $key (keys %vals) {
            $ref->{$key} = $vals{$key};
        }
        $self->_dirty( $ref, $id );
        $self->_store_weak( $id, $ref );
        return $id;
    }
    else {
        return $ref->{ID} if $ref->{ID};
        if( $class eq 'Yote::Root' ) {
            $ref->{ID} = $self->{_DATASTORE}->_first_id( $class );
        } else {
            $ref->{ID} ||= $self->{_DATASTORE}->_get_id( $class );
        }

        return $ref->{ID};
    }

} #_get_id

sub _stow {
    my( $self, $obj, $id ) = @_;

    my $class = ref( $obj );
    return unless $class;
    $id //= $self->_get_id( $obj );
    die unless $id;

    my $data = $self->_raw_data( $obj );

    if( $class eq 'ARRAY' ) {
        $self->{_DATASTORE}->_stow( $id,'ARRAY', $data );
        $self->_clean( $id );
    }
    elsif( $class eq 'HASH' ) {
        $self->{_DATASTORE}->_stow( $id,'HASH',$data );
        $self->_clean( $id );
    }
    elsif( $class eq 'Yote::Array' ) {
        if( $self->_is_dirty( $id ) ) {
            $self->{_DATASTORE}->_stow( $id,'ARRAY',$data );
            $self->_clean( $id );
        }
        for my $child (@$data) {
            if( $child =~ /^[0-9]/ && $self->{_DIRTY}->{$child} ) {
                $self->_stow( $child, $self->{_DIRTY}->{$child} );
            }
        }
    }
    elsif( $class eq 'Yote::Hash' ) {
        if( $self->_is_dirty( $id ) ) {
            $self->{_DATASTORE}->_stow( $id, 'HASH', $data );
        }
        $self->_clean( $id );
        for my $child (values %$data) {
            if( $child =~ /^[0-9]/ && $self->{_DIRTY}->{$child} ) {
                $self->_stow( $child, $self->{_DIRTY}->{$child} );
            }
        }
    }
    else {
        if( $self->_is_dirty( $id ) ) {
            $self->{_DATASTORE}->_stow( $id, $class, $data );
            $self->_clean( $id );
        }
        for my $val (values %$data) {
            if( $val =~ /^[0-9]/ && $self->{_DIRTY}->{$val} ) {
                $self->_stow( $val, $self->{_DIRTY}->{$val} );
            }
        }
    }
    $id;
} #_stow

sub _xform_in {
    my( $self, $val ) = @_;
    if( ref( $val ) ) {
        return $self->_get_id( $val );
    }
    return defined $val ? "v$val" : undef;
}

sub _xform_out {
    my( $self, $val ) = @_;
    return undef unless defined( $val );
    if( index($val,'v') == 0 ) {
        return substr( $val, 1 );
    }
    return $self->fetch( $val );
}

sub _clean {
    my( $self, $id ) = @_;
    delete $self->{_DIRTY}{$id};
} #_clean

sub _is_dirty {
    my( $self, $obj ) = @_;
    my $id = ref($obj) ? _get_id($obj) : $obj;
    my $ans = $self->{_DIRTY}{$id};
    $ans;
} #_is_dirty

sub _has_weak_refs {
    my $self = shift;

    # if there is an ARRAY or HASH, since it is tied, it has a reference to itself
    0 < grep { $_ && refcount($_) > (ref($_) =~ /^(ARRAY|HASH)$/ ? 1 : 0 ) }
        values %{$self->{_WEAK_REFS}};
}

sub _purge {
    my $self = shift;
    $self->{_DIRTY} = {};
    $self->{_WEAK_REFS} = {};
}

#
# Returns data structure representing object. References are integers. Values start with 'v'.
#
sub _raw_data {
    my( $self, $obj ) = @_;
    my $class = ref( $obj );
    return unless $class;
    my $id = $self->_get_id( $obj );
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

} #_raw_data

sub _store_weak {
    my( $self, $id, $ref ) = @_;
    die unless $ref;
    $self->{_WEAK_REFS}{$id} = $ref;

    weaken( $self->{_WEAK_REFS}{$id} );
} #_store_weak

# ---------------------------------------------------------------------------------------------------------------------

=head1 NAME

 Yote::Obj - Generic container object for graph.

=head1 DESCRIPTION

A Yote::Obj is a container class that as a specific idiom for getters
and setters. This idiom is set up to avoid confusion and collision
with any method names.

 # sets the 'foo' field to the given value.
 $obj->set_foo( { value => $store->newobj } );

 # returns the value for bar, and if none, sets it to 'default'
 my $bar = $obj->get_bar( "default" );

 $obj->add_to_somelist( "Freddish" );
 my $list = $obj->get_somelist;
 $list->[ 0 ] == "Freddish";


 $obj->remove_from_somelist( "Freddish" );

=cut
package Yote::Obj;

use strict;
use warnings;
no  warnings 'uninitialized';

#
# The string version of the yote object is simply its id. This allows
# objet ids to easily be stored as hash keys.
#
use overload
    '""' => sub { shift->{ID} }, # for hash keys
    eq   => sub { ref($_[1]) && $_[1]->{ID} == $_[0]->{ID} },
    ne   => sub { ! ref($_[1]) || $_[1]->{ID} != $_[0]->{ID} },
    '=='   => sub { ref($_[1]) && $_[1]->{ID} == $_[0]->{ID} },
    '!='   => sub { ! ref($_[1]) || $_[1]->{ID} != $_[0]->{ID} },
    fallback => 1;

=head2 absorb( hashref )

    pulls the hash data into this object.

=cut
sub absorb {
    my( $self, $data ) = @_;
    my $obj_store = $self->{STORE};
    for my $key ( sort keys %$data ) {
        my $item = $data->{ $key };
        $self->{DATA}{$key} = $obj_store->_xform_in( $item );
    }
    $obj_store->_dirty( $self, $self->{ID} );

} #absorb

sub id {
    shift->{ID};
}

=head2 set( $field, $value )

    Assigns the given value to the field in this object and returns the
    assigned value.

=cut
sub set {
    my( $self, $fld, $val ) = @_;

    my $inval = $self->{STORE}->_xform_in( $val );
    if( $self->{DATA}{$fld} ne $inval ) {
        $self->{STORE}->_dirty( $self, $self->{ID} );
    }


    $self->{DATA}{$fld} = $inval;
    return $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
} #set


=head2 get( $field, $default-value )

    Returns the value assigned to the field, assinging the default
    value to it if the value is currently not defined.

=cut
sub get {
    my( $self, $fld, $default ) = @_;
    my $cur = $self->{DATA}{$fld};
    if( ! defined( $cur ) && defined( $default ) ) {
        if( ref( $default ) ) {
            # this must be done to make sure the reference is saved for cases where the reference has not yet made it to the store of things to save
            $self->{STORE}->_dirty( $default->{STORE}->_get_id( $default ) );
        }
        $self->{STORE}->_dirty( $self, $self->{ID} );
        $self->{DATA}{$fld} = $self->{STORE}->_xform_in( $default );
    }
    return $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
} #get


# -----------------------
#
#     Public Methods
# -----------------------
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
            my $inval = $self->{STORE}->_xform_in( $val );
            $self->{STORE}->_dirty( $self, $self->{ID} ) if $self->{DATA}{$fld} ne $inval;
            $self->{DATA}{$fld} = $inval;

            return $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
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
                    # this must be done to make sure the reference is saved for cases where the reference has not yet made it to the store of things to save
                    $self->{STORE}->_dirty( $init_val, $self->{STORE}->_get_id( $init_val ) );
                }
                $self->{STORE}->_dirty( $self, $self->{ID} );
                $self->{DATA}{$fld} = $self->{STORE}->_xform_in( $init_val );
            }
            return $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    }
    else {
        die "Unknown Yote::Obj function '$func'";
    }

} #AUTOLOAD

# -----------------------
#
#     Overridable Methods
# -----------------------

=head2 _init

    This is called the first time an object is created. It is not
    called when the object is loaded from storage. This can be used
    to set up defaults. This is meant to be overridden.

=cut
sub _init {}

=head2 _init

    This is called each time the object is loaded from the data store.
    This is meant to be overridden.

=cut
sub _load {}



# -----------------------
#
#     Private Methods
#
# -----------------------


sub _new { #new Yote::Obj
    my( $pkg, $obj_store, $data, $_id ) = @_;

    my $class = ref($pkg) || $pkg;
    my $obj = bless {
        DATA     => {},
        STORE    => $obj_store,
    }, $class;
    $obj->{ID} = $_id || $obj_store->_get_id( $obj );
    $obj_store->_dirty( $obj, $obj->{ID} );
    $obj->_init(); #called the first time the object is created.

    if( ref( $data ) eq 'HASH' ) {
        $obj->absorb( $data );
    } elsif( $data ) {
        die "Yote::Obj::new must be called with hash or undef. Was called with '". ref( $data ) . "'";
    }
    return $obj;
} #_new

sub _store {
    return shift->{STORE};
}

#
# Called by the object provider; returns a Yote::Obj the object
# provider will stuff data into. Takes the class and id as arguments.
#
sub _instantiate {
    bless { ID => $_[1], DATA => {}, STORE => $_[2] }, $_[0];
} #_instantiate

sub DESTROY {}

sub _DUMP_ALL {
    my( $self, $seen, $show ) = @_;
    $seen //= {};
    $show //= {};

    delete $show->{$self->{ID}};
    $seen->{$self->{ID}} = 1;
    my $buf = $self->_DUMP;

    for my $obj_id (sort { $a <=> $b } grep { index($_,'v') != 0 && 0 == $seen->{$_}++ } values %{$self->{DATA}}) {
        $show->{$obj_id} = 1;
    }

    while(1) {
        my( $obj_id ) = keys %$show;
        last unless $obj_id;
        $buf .= "-------------------------\n";

        my $obj = $self->{STORE}->fetch( $obj_id );
        my $r = ref( $obj );

        if( $r eq 'ARRAY' ) {
            $buf .= "$obj_id (ARRAY)\n";
            my $tied = tied @$obj;
            delete $show->{$obj_id};
            for my $item (@{$tied->[1]}) {
                if( $item > 0 ) {
                    $show->{$item} = 1;
                    $buf .= "\t* $item\n";
                } else {
                    $buf .= "\t".substr($item,1)."\n";
                }
            }
        }
        elsif( $r eq 'HASH' ) {
            $buf .= "$obj_id (HASH)\n";
            delete $show->{$obj_id};
            my $tied = tied %$obj;
            my $th = $tied->[1];
            for my $key (keys %$th) {
                my $item = $th->{$key};

                if( $item > 0 ) {
                    $show->{$item} = 1;
                    $buf .= "\t$key -> * $item\n";
                } else {
                    $buf .= "\t$key -> ".substr($item,1)."\n";
                }
            }
        }
        else {
            $buf .= $obj->_DUMP_ALL( $seen, $show );
        }
    }
    $buf;
} #_DUMP_ALL

sub _DUMP {
    my $self = shift;
    my $buf = "$self->{ID} (".ref($self).")\n";
    for my $key (sort keys %{$self->{DATA}}) {
        my $val = $self->{DATA}{$key};
        if( index( $val, 'v' ) != 0 ) {
            $buf .= "\t$key -> * $val \n";
        } else {
            $buf .= "\t$key -> ".substr($val,1)."\n";
        }
    }
    $buf;
} #_DUMP

# ---------------------------------------------------------------------------------------------------------------------

package Yote::Array;

############################################################################################################
# This module is used transparently by Yote to link arrays into its graph structure. This is not meant to  #
# be called explicitly or modified.									   #
############################################################################################################

use strict;
use warnings;

no warnings 'uninitialized';
use Tie::Array;

sub TIEARRAY {
    my( $class, $obj_store, $id, @list ) = @_;
    my $storage = [];

    # once the array is tied, an additional data field will be added
    # so obj will be [ $id, $storage, $obj_store ]
    my $obj = bless [$id,$storage,$obj_store], $class;
    for my $item (@list) {
        push( @$storage, $item );
    }
    return $obj;
}

sub FETCH {
    my( $self, $idx ) = @_;
    return $self->[2]->_xform_out ( $self->[1][$idx] );
}

sub FETCHSIZE {
    my $self = shift;
    return scalar(@{$self->[1]});
}

sub STORE {
    my( $self, $idx, $val ) = @_;
    $self->[2]->_dirty( $self->[3], $self->[0] );
    $self->[1][$idx] = $self->[2]->_xform_in( $val );
}
sub STORESIZE {}  #stub for array

sub EXISTS {
    my( $self, $idx ) = @_;
    return defined( $self->[1][$idx] );
}
sub DELETE {
    my( $self, $idx ) = @_;
    $self->[2]->_dirty( $self->[3], $self->[0] );
    delete $self->[1][$idx];
}

sub CLEAR {
    my $self = shift;
    $self->[2]->_dirty( $self->[3], $self->[0] );
    @{$self->[1]} = ();
}
sub PUSH {
    my( $self, @vals ) = @_;
    $self->[2]->_dirty( $self->[3], $self->[0] );
    push( @{$self->[1]}, map { $self->[2]->_xform_in($_) } @vals );
}
sub POP {
    my $self = shift;
    $self->[2]->_dirty( $self->[3], $self->[0] );
    return $self->[2]->_xform_out( pop @{$self->[1]} );
}
sub SHIFT {
    my( $self ) = @_;
    $self->[2]->_dirty( $self->[3], $self->[0] );
    my $val = splice @{$self->[1]}, 0, 1;
    return $self->[2]->_xform_out( $val );
}
sub UNSHIFT {
    my( $self, @vals ) = @_;
    $self->[2]->_dirty( $self->[3], $self->[0] );
    unshift @{$self->[1]}, map {$self->[2]->_xform_in($_)} @vals;
}
sub SPLICE {
    my( $self, $offset, $length, @vals ) = @_;
    $self->[2]->_dirty( $self->[3], $self->[0] );
    return map { $self->[2]->_xform_out($_) } splice @{$self->[1]}, $offset, $length, map {$self->[2]->_xform_in($_)} @vals;
}
sub EXTEND {}

sub DESTROY {}

# ---------------------------------------------------------------------------------------------------------------------

package Yote::Hash;

############################################################################################################
# This module is used transparently by Yote to link hashes into its graph structure. This is not meant to  #
# be called explicitly or modified.									   #
############################################################################################################

use strict;
use warnings;

no warnings 'uninitialized';

use Tie::Hash;

sub TIEHASH {
    my( $class, $obj_store, $id, %hash ) = @_;
    my $storage = {};
    # after $obj_store is a list reference of
    #                 id, data, store
    my $obj = bless [ $id, $storage,$obj_store ], $class;
    for my $key (keys %hash) {
        $storage->{$key} = $hash{$key};
    }
    return $obj;
}

sub STORE {
    my( $self, $key, $val ) = @_;
    $self->[2]->_dirty( $self->[3], $self->[0] );
    $self->[1]{$key} = $self->[2]->_xform_in( $val );
}

sub FIRSTKEY {
    my $self = shift;
    my $a = scalar keys %{$self->[1]};
    my( $k, $val ) = each %{$self->[1]};
    return wantarray ? ( $k => $val ) : $k;
}
sub NEXTKEY  {
    my $self = shift;
    my( $k, $val ) = each %{$self->[1]};
    return wantarray ? ( $k => $val ) : $k;
}

sub FETCH {
    my( $self, $key ) = @_;
    return $self->[2]->_xform_out( $self->[1]{$key} );
}

sub EXISTS {
    my( $self, $key ) = @_;
    return defined( $self->[1]{$key} );
}
sub DELETE {
    my( $self, $key ) = @_;
    $self->[2]->_dirty( $self->[3], $self->[0] );
    return delete $self->[1]{$key};
}
sub CLEAR {
    my $self = shift;
    $self->[2]->_dirty( $self->[3], $self->[0] );
    %{$self->[1]} = ();
}

sub DESTROY {}

# ---------------------------------------------------------------------------------------------------------------------

package Yote::YoteDB;

use strict;
use warnings;

no warnings 'uninitialized';

use Data::RecordStore;

use WeakRef;
use File::Path qw(make_path);
use JSON;

use Devel::Refcount 'refcount';

use constant {
  DATA => 2,
};

#
# This the main index and stores in which table and position
# in that table that this object lives.
#
sub open {
  my( $pkg, $obj_store, $args ) = @_;
  my $class = ref( $pkg ) || $pkg;

  my $self = bless {
      args       => $args,
      OBJ_STORE  => $obj_store,
      DATA_STORE => Data::RecordStore->open( $args->{ store } ),
  }, $class;
  $self->{DATA_STORE}->ensure_entry_count( 1 );
  $self;
} #open

#
# Return a list reference containing [ id, class, data ] that
# corresponds to the $id argument. This is used by Yote::ObjStore
# to build the yote object.
#
sub _fetch {
  my( $self, $id ) = @_;
  my $data = $self->{DATA_STORE}->fetch( $id );
  return undef unless $data;

  my $pos = index( $data, ' ' ); #there is a always a space after the class.
  die "Malformed record '$data'" if $pos == -1;
  my $class = substr $data, 0, $pos;
  my $val   = substr $data, $pos + 1;
  my $ret = [$id,$class,$val];
  $ret->[DATA] = from_json( $ret->[DATA] );
  $ret;
} #_fetch

#
# The first object in a yote data store can trace a reference to
# all active objects.
#
sub _first_id {
  return 1;
} #_first_id

#
# Create a new object id and return it.
#
sub _get_id {
  my $self = shift;
  $self->{DATA_STORE}->next_id;
} #_get_id


# used for debugging and testing
sub _max_id {
  shift->{DATA_STORE}->entry_count;
}

sub _recycle_objects {
  my $self = shift;

  my $mark_to_keep_store = Data::RecordStore::FixedStore->open( "I", $self->{args}{store} . '/RECYCLE' );
  $mark_to_keep_store->empty();
  $mark_to_keep_store->ensure_entry_count( $self->{DATA_STORE}->entry_count );
  
  # the already deleted cannot be re-recycled
  my $ri = $self->{DATA_STORE}->_get_recycled_ids;
  for ( @$ri ) {
    $mark_to_keep_store->put_record( $_, [ 1 ] );
  }

  my $trace_to_root = sub {
      my( $keep_id, $mark_to_keep_store ) = @_;
      my( @queue ) = ( $keep_id );

      $mark_to_keep_store->put_record( $keep_id, [ 1 ] );

      # get the object ids referenced by this keeper object
      while( @queue ) {
          $keep_id = shift @queue;

          my $item = $self->_fetch( $keep_id );
          my( @additions );
          if ( ref( $item->[DATA] ) eq 'ARRAY' ) {
              ( @additions ) = grep { /^[^v]/ } @{$item->[DATA]};
          } else {
              ( @additions ) = grep { /^[^v]/ } values %{$item->[DATA]};
          }

          for my $keeper ( @additions ) {
              next if $mark_to_keep_store->get_record( $keeper )->[0];
              $mark_to_keep_store->put_record( $keeper, [ 1 ] );
              push @queue, $keeper;
          }
      } #while there is a queue
  };

  &$trace_to_root( $self->_first_id, $mark_to_keep_store );

  #
  # If there are any entries in the weak references, do not recycle these.
  # This ignores the possibility of circular references, but that uncommon case
  # is not worth the complexity.
  #
  for my $referenced_id ( grep { defined($self->{OBJ_STORE}{_WEAK_REFS}{$_}) } keys %{ $self->{OBJ_STORE}{_WEAK_REFS} } ) {
      # make sure that these are actually referenced. They may be 
      # in DIRTY, and, if they are Yote::Array or Yote::Hash, they
      # have an extra reference due to the tie.
      my $obj = $self->{OBJ_STORE}->fetch( $referenced_id );
      my $min_ref_count = 1;
      if( $self->{OBJ_STORE}->_is_dirty( $referenced_id ) ) {
          $min_ref_count++;
      }
      $min_ref_count++ if ref($obj) =~ /^(ARRAY|HASH)$/;

      if( refcount($obj) > $min_ref_count ) {
          &$trace_to_root( $referenced_id, $mark_to_keep_store );
      }
  }

  # the purge begins here
  my $cands = $self->{DATA_STORE}->entry_count;
  my $count = 0;
  for my $cand ( 1..$cands) { #iterate each id in the entire object store
    my( $keep ) = $mark_to_keep_store->get_record( $cand )->[0];

    die "Tried to recycle root entry" if $cand == 1 && ! $keep;
    if ( ! $keep ) {
        $self->{DATA_STORE}->recycle( $cand );
        delete $self->{OBJ_STORE}{_WEAK_REFS}{$cand};
        $count++;
    }
  }

  # remove temporary recycle datastore
  $mark_to_keep_store->unlink_store;

  $self->{DATA_STORE}->_get_recycled_ids;
  
} #_recycle_objects


#
# Saves the object data for object $id to the data store.
#
sub _stow { #Yote::YoteDB::_stow
  my( $self, $id, $class, $data ) = @_;
  my $save_data = "$class " . to_json($data);
  $self->{DATA_STORE}->stow( $save_data, $id );
} #_stow

#
# Takes a list of object data references and stows them all in the datastore.
# returns how many are stowed.
#
sub _stow_all {
  my( $self, $objs ) = @_;
  my $count = 0;
  for my $o ( @$objs ) {
    $count += $self->_stow( @$o );
  }
  return $count;
} #_stow_all

1;

__END__

=head1 AUTHOR
       Eric Wolf        coyocanid@gmail.com

=head1 COPYRIGHT AND LICENSE

       Copyright (c) 2016 Eric Wolf. All rights reserved.  This program is free software; you can redistribute it and/or modify it
       under the same terms as Perl itself.

=head1 VERSION
       Version 1.44  (Nov 23, 2016))

=cut
