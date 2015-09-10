package Yote::Obj;

use strict;
use warnings;
no warnings 'uninitialized';

use vars qw($VERSION);

$VERSION = '1.0';

=head1 NAME

Yote::Obj - Persistant Perl container objects in a directed graph.

=head1 SYNOPSIS
 
 use Yote;

 my $store = Yote::open_store( '/path/to/data-directory' );

 my $root_node = $store->fetch_root;

 $root_node->add_to_myList( $store->newobj( { 
    someval => 123.53,
    someobj => $store->newobj( { foo => "Bar" } );
 } );
 
 $root_node->add_to_myList( 42 );

 $root_node->set_field( "Value" );

 my $val = $root_node->get_value( "default" );
 # $val eq 'default'

 $root_node->set_value( "Something Else" );

 my $val = $root_node->get_value( "default" );
 # $val eq 'Something Else'

 my $myList = $root_node->get_myList;

 for my $example (@$myList) {
    print ">$example\n";
 }

 $myList->[0]->set_condition( "About to be recycled" );
 delete $myList->[0];

 $store->stow_all;
 $store->run_recycler;

=cut


=head2 open_store( '/path/to/directory' )

Starts up a persistance engine with the arguments passed in.
This must be called before any use of t
   
=cut
our $Yote::STORES = {};
sub open_store {
    my $path = pop;
    $Yote::STORES->{$path} ||= new Yote::ObjProvider( $path );
    $Yote::STORES->{$path};
}

package Yote::Obj;

use strict;
use warnings;
no warnings 'uninitialized';

use vars qw($VERSION);

$VERSION = '0.1';

#
# The string version of the yote object is simply its id. This allows
# objet ids to easily be stored as hash keys.
#
# use overload
#     '""' => sub { shift->{ID} }, # for hash keys
#     eq   => sub { ref($_[1]) && $_[1]->{ID} == $_[0]->{ID} },
#     ne   => sub { ! ref($_[1]) || $_[1]->{ID} != $_[0]->{ID} },
#     '=='   => sub { ref($_[1]) && $_[1]->{ID} == $_[0]->{ID} },
#     '!='   => sub { ! ref($_[1]) || $_[1]->{ID} != $_[0]->{ID} },
#     fallback => 1;

=head2 new( { ... data .... } )

 Creates a new data object initialized with the incoming hash ref data.
 Once created, the object will be saved in the data store when 
 Yote::Obj::stow_all has been called.  If the object is not attached 
 to the root or an object that can be reached by the root, it will be 
 recycled when Yote::Obj::recycle_objects is called.

=cut
sub new {
    my( $pkg, $data ) = @_;
    unless( $Yote::Obj::__OBJ_PROVIDER ) { die "Yote::Obj::init must be called before new is called"; }
    my $class = ref($pkg) || $pkg;

    my $obj = bless {
        ID       => undef,
        DATA     => {},
    }, $class;
    $obj->{ID} = $Yote::Obj::__OBJ_PROVIDER->get_id( $obj );
    $obj->_init(); #called the first time the object is created.
    $Yote::Obj::__OBJ_PROVIDER->dirty( $obj, $obj->{ID} );
    if( ref( $data ) eq 'HASH' ) {
        for my $key ( sort keys %$data ) {
            $obj->{DATA}{$key} = $Yote::Obj::__OBJ_PROVIDER->xform_in( $data->{ $key } );
        }
        $Yote::Obj::__OBJ_PROVIDER->dirty( $obj, $obj->{ID} );
    } elsif( $data ) {
        die "Yote::Obj::new must be called with hash or undef. Was called with '". ref( $data ) . "'";
    }
    return $obj;
} #new

=head2 fetch_by_id( db-id )

 Returns the yote object with the given db id, if it exists.

=cut
sub fetch_by_id {
    unless( $Yote::Obj::__OBJ_PROVIDER ) { die "Yote::Obj::init must be called before fetch_id is called"; }
    return $Yote::Obj::__OBJ_PROVIDER->fetch( $_[$#_] );
}

=head2 fetch_root()

 Returns the Yote root object that is the entry point to the
 directed graph.

=cut
sub fetch_root {
    Yote::Root::fetch_root();
}

=head2 fun_recycler()

 Removes all objects that cannot be traced back to the Yote root object.

=cut
sub run_recycler {
    unless( $Yote::Obj::__OBJ_PROVIDER ) { die "Yote::Obj::init must be called before run_recycler is called"; }
    $Yote::Obj::__OBJ_PROVIDER->recycle_objects;
}

=head2 stow_all()

 Saves all the objects in the directory provided in the init.

=cut
sub stow_all {
    unless( $Yote::Obj::__OBJ_PROVIDER ) { die "Yote::Obj::init must be called before stow_all is called"; }
    $Yote::Obj::__OBJ_PROVIDER->stow_all;
}

# -----------------------
#
#     Overridable Methods
#
# -----------------------

#
# Called the very first time this object is created. It is not called
# when object is loaded from storage.
#
sub _init {}

#
# Called each time the object is loaded from the data store.
#
sub _load {}


# -----------------------
#
#     Private Methods
#
# -----------------------

#
# Called by the object provider; returns a Yote::Obj the object
# provider will stuff data into. Takes the class and id as arguments.
#
sub _instantiate {
    bless { ID => $_[1], DATA => {} }, $_[0];
} #_instantiate

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
            my $inval = $Yote::Obj::__OBJ_PROVIDER->xform_in( $val );
            $Yote::Obj::__OBJ_PROVIDER->dirty( $self, $self->{ID} ) if $self->{DATA}{$fld} ne $inval;
            $self->{DATA}{$fld} = $inval;

            return $Yote::Obj::__OBJ_PROVIDER->xform_out( $self->{DATA}{$fld} );
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
                    $Yote::Obj::__OBJ_PROVIDER->dirty( $init_val, $Yote::Obj::__OBJ_PROVIDER->get_id( $init_val ) );
                }
                $Yote::Obj::__OBJ_PROVIDER->dirty( $self, $self->{ID} );
                $self->{DATA}{$fld} = $Yote::Obj::__OBJ_PROVIDER->xform_in( $init_val );
            }
            return $Yote::Obj::__OBJ_PROVIDER->xform_out( $self->{DATA}{$fld} );
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    }
    else {
        die "Unknown Yote::Obj function '$func'";
    }

} #AUTOLOAD

package Yote::ObjProvider;

use strict;
use warnings;
no warnings 'numeric';
no warnings 'uninitialized';
no warnings 'recursion';

use Crypt::Passwd::XS;
use WeakRef;


use vars qw($VERSION);

$VERSION = '0.073';


# ------------------------------------------------------------------------------------------
#      * INIT METHODS *
# ------------------------------------------------------------------------------------------
sub new {
    my( $pkg, $args ) = @_;
    my $self = bless {
        __DIRTY     => {},
        __WEAK_REFS => {},
    }, $_[0];
    $self->{__DATASTORE} = new Yote::YoteDB( $self, $_[1] );
    $self;
} #init

# ------------------------------------------------------------------------------------------
#      * PUBLIC CLASS METHODS *
# ------------------------------------------------------------------------------------------

sub fetch_root {
    my $self = shift;
    die "fetch_root must be called on Yote store object" unless ref( $self );
    my $root = $self->fetch( $self->first_id );
    unless( $root ) {
        $root = new Yote::Obj;
        $self->stow( $root );
    }
    $root;
} #fetch_root

#
# Markes given object as dirty.
#
sub dirty {
    # ( $self, $ref, $id
    $_[0]->{__DIRTY}->{$_[2]} = $_[1];
} #dirty

sub fetch {
    my( $self, $id ) = @_;
    return undef unless $id;
    #
    # Return the object if we have a reference to its dirty state.
    #
    my $ref = $self->{__DIRTY}->{$id} || $self->{__WEAK_REFS}->{$id};

    if( defined $ref ) {
        return $ref;
    }
    my $obj_arry = $self->{__DATASTORE}->fetch( $id );

    if( $obj_arry ) {
        my( $id, $class, $data ) = @$obj_arry;
        if( $class eq 'ARRAY' ) {
            my( @arry );
            tie @arry, 'Yote::Array', $id, @$data;
            my $tied = tied @arry; $tied->[2] = \@arry;
            $self->__store_weak( $id, \@arry );
            return \@arry;
        }
        elsif( $class eq 'HASH' ) {
            my( %hash );
            tie %hash, 'Yote::Hash', $id, map { $_ => $data->{$_} } keys %$data;
            my $tied = tied %hash; $tied->[2] = \%hash;
            $self->__store_weak( $id, \%hash );
            return \%hash;
        }
        else {
            $class =~ /^Yote::(Root|Obj)/ || eval("require $class");
            return undef if $@;

            my $obj = $class->_instantiate( $id );
            $obj->{DATA} = $data;
            $obj->{ID} = $id;
            $obj->_load();
            $self->__store_weak( $id, $obj );
            return $obj;
        }
    }

    return undef;
} #fetch


#
# Returns the first ID that is associated with the root Root object
#
sub first_id {
    shift->{__DATASTORE}->first_id();
}

sub get_id {
    my( $self, $ref ) = @_;
    my $class = ref( $ref );
    if( $class eq 'Yote::Array') {
        return $ref->[0];
    }
    elsif( $class eq 'ARRAY' ) {
        my $tied = tied @$ref;
        if( $tied ) {
            $tied->[0] ||= $self->{__DATASTORE}->get_id( "ARRAY" );
            $self->__store_weak( $tied->[0], $ref );
            return $tied->[0];
        }
        my( @data ) = @$ref;
        my $id = $self->{__DATASTORE}->get_id( $class );
        tie @$ref, 'Yote::Array', $id;
        $tied = tied @$ref; $tied->[2] = $ref;
        push( @$ref, @data );
        $self->dirty( $ref, $id );
        $self->__store_weak( $id, $ref );
        return $id;
    }
    elsif( $class eq 'Yote::Hash' ) {
        my $wref = $ref;
        return $ref->[0];
    }
    elsif( $class eq 'HASH' ) {
        my $tied = tied %$ref;
        if( $tied ) {
            $tied->[0] ||= $self->{__DATASTORE}->get_id( "HASH" );
            $self->__store_weak( $tied->[0], $ref );
            return $tied->[0];
        }
        my $id = $self->{__DATASTORE}->get_id( $class );
        my( %vals ) = %$ref;
        tie %$ref, 'Yote::Hash', $id;
        $tied = tied %$ref; $tied->[2] = $ref;
        for my $key (keys %vals) {
            $ref->{$key} = $vals{$key};
        }
        $self->dirty( $ref, $id );
        $self->__store_weak( $id, $ref );
        return $id;
    }
    else {
        if( $class eq 'Yote::Root' ) {
            $ref->{ID} = $self->{__DATASTORE}->first_id( $class );
        } else {
            $ref->{ID} ||= $self->{__DATASTORE}->get_id( $class );
        }
        $self->__store_weak( $ref->{ID}, $ref );
        return $ref->{ID};
    }

} #get_id

sub recycle_objects {
    my $self = shift;
    $self->stow_all();
    $self->{__DATASTORE}->recycle_objects();
} #recycle_objects

sub stow {
    my( $self, $obj ) = @_;

    my $class = ref( $obj );
    return unless $class;
    my $id = $self->get_id( $obj );
    die unless $id;

    my $data = $self->__raw_data( $obj );
    if( $class eq 'ARRAY' ) {
        $self->{__DATASTORE}->stow( $id,'ARRAY', $data );
        $self->__clean( $id );
    }
    elsif( $class eq 'HASH' ) {
        $self->{__DATASTORE}->stow( $id,'HASH',$data );
        $self->__clean( $id );
    }
    elsif( $class eq 'Yote::Array' ) {
        if( $self->__is_dirty( $id ) ) {
            $self->{__DATASTORE}->stow( $id,'ARRAY',$data );
            $self->__clean( $id );
        }
        for my $child (@$data) {
            if( $child =~ /^[0-9]/ && $self->{__DIRTY}->{$child} ) {
                $self->stow( $self->{__DIRTY}->{$child} );
            }
        }
    }
    elsif( $class eq 'Yote::Hash' ) {
        if( $self->__is_dirty( $id ) ) {
            $self->{__DATASTORE}->stow( $id, 'HASH', $data );
        }
        $self->__clean( $id );
        for my $child (values %$data) {
            if( $child =~ /^[0-9]/ && $self->{__DIRTY}->{$child} ) {
                $self->stow( $self->{__DIRTY}->{$child} );
            }
        }
    }
    else {
        if( $self->__is_dirty( $id ) ) {
            $self->{__DATASTORE}->stow( $id, $class, $data );
            $self->__clean( $id );
        }
        for my $val (values %$data) {
            if( $val =~ /^[0-9]/ && $self->{__DIRTY}->{$val} ) {
                $self->stow( $self->{__DIRTY}->{$val} );
            }
        }
    }
} #stow

sub stow_all {
    my $self = $_[0];
    my @odata;
    for my $obj (values %{$self->{__DIRTY}} ) {
        my $cls;
        my $ref = ref( $obj );
        if( $ref eq 'ARRAY' || $ref eq 'Yote::Array' ) {
            $cls = 'ARRAY';
        } elsif( $ref eq 'HASH' || $ref eq 'Yote::Hash' ) {
            $cls = 'HASH';
        } else {
            $cls = $ref;
        }
        push( @odata, [ $self->get_id( $obj ), $cls, $self->__raw_data( $obj ) ] );
    }
    $self->{__DATASTORE}->stow_all( \@odata );
    $self->{__DIRTY} = {};
} #stow_all

sub xform_in {
    my( $self, $val ) = @_;
    if( ref( $val ) ) {
        return $self->get_id( $val );
    }
    return "v$val";
}

sub xform_out {
    my( $self, $val ) = @_;
    return undef unless defined( $val );
    if( index($val,'v') == 0 ) {
        return substr( $val, 1 );
    }
    return $self->fetch( $val );
}



# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

sub __clean {
    my( $self, $id ) = @_;
    delete $self->{__DIRTY}{$id};
} #__clean

sub __is_dirty {
    my( $self, $obj ) = @_;
    my $id = ref($obj) ? get_id($obj) : $obj;
    return $self->{__DIRTY}{$id};
} #__is_dirty

#
# Returns data structure representing object. References are integers. Values start with 'v'.
#
sub __raw_data {
    my( $self, $obj ) = @_;
    my $class = ref( $obj );
    return unless $class;
    my $id = $self->get_id( $obj );
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
    my( $self, $id, $ref ) = @_;
    $self->{__WEAK_REFS}{$id} = $ref;
    weaken( $self->{__WEAK_REFS}{$id} );
} #__store_weak

package Yote::Array;

############################################################################################################
# This module is used transparently by Yote to link arrays into its graph structure. This is not meant to  #
# be called explicitly or modified.									   #
############################################################################################################

use strict;
use warnings;

no warnings 'uninitialized';
use Tie::Array;

use vars qw($VERSION);

$VERSION = '0.02';

sub TIEARRAY {
    my( $class, $id, @list ) = @_;
    my $storage = [];
    my $obj = bless [$id,$storage], $class;
    for my $item (@list) {
        push( @$storage, $item );
    }
    return $obj;
}

sub FETCH {
    my( $self, $idx ) = @_;
    return $Yote::Obj::__OBJ_PROVIDER->xform_out ( $self->[1][$idx] );
}

sub FETCHSIZE {
    my $self = shift;
    return scalar(@{$self->[1]});
}

sub STORE {
    my( $self, $idx, $val ) = @_;
    $Yote::Obj::__OBJ_PROVIDER->dirty( $self->[2], $self->[0] );
    $self->[1][$idx] = $Yote::Obj::__OBJ_PROVIDER->xform_in( $val );
}
sub STORESIZE {}  #stub for array

sub EXISTS {
    my( $self, $idx ) = @_;
    return defined( $self->[1][$idx] );
}
sub DELETE {
    my( $self, $idx ) = @_;
    $Yote::Obj::__OBJ_PROVIDER->dirty( $self->[2], $self->[0] );
    delete $self->[1][$idx];
}

sub CLEAR {
    my $self = shift;
    $Yote::Obj::__OBJ_PROVIDER->dirty( $self->[2], $self->[0] );
    @{$self->[1]} = ();
}
sub PUSH {
    my( $self, @vals ) = @_;
    $Yote::Obj::__OBJ_PROVIDER->dirty( $self->[2], $self->[0] );
    push( @{$self->[1]}, map { $Yote::Obj::__OBJ_PROVIDER->xform_in($_) } @vals );
}
sub POP {
    my $self = shift;
    $Yote::Obj::__OBJ_PROVIDER->dirty( $self->[2], $self->[0] );
    return $Yote::Obj::__OBJ_PROVIDER->xform_out( pop @{$self->[1]} );
}
sub SHIFT {
    my( $self ) = @_;
    $Yote::Obj::__OBJ_PROVIDER->dirty( $self->[2], $self->[0] );
    my $val = splice @{$self->[1]}, 0, 1;
    return $Yote::Obj::__OBJ_PROVIDER->xform_out( $val );
}
sub UNSHIFT {
    my( $self, @vals ) = @_;
    $Yote::Obj::__OBJ_PROVIDER->dirty( $self->[2], $self->[0] );
    unshift @{$self->[1]}, map {$Yote::Obj::__OBJ_PROVIDER->xform_in($_)} @vals;
}
sub SPLICE {
    my( $self, $offset, $length, @vals ) = @_;
    $Yote::Obj::__OBJ_PROVIDER->dirty( $self->[2], $self->[0] );
    return map { $Yote::Obj::__OBJ_PROVIDER->xform_out($_) } splice @{$self->[1]}, $offset, $length, map {$Yote::Obj::__OBJ_PROVIDER->xform_in($_)} @vals;
}
sub EXTEND {}

sub DESTROY {}

package Yote::Hash;

############################################################################################################
# This module is used transparently by Yote to link hashes into its graph structure. This is not meant to  #
# be called explicitly or modified.									   #
############################################################################################################

use strict;
use warnings;

no warnings 'uninitialized';

use Tie::Hash;

use vars qw($VERSION);

$VERSION = '0.02';

sub TIEHASH {
    my( $class, $id, %hash ) = @_;
    my $storage = {};
    my $obj = bless [ $id, $storage ], $class;
    for my $key (keys %hash) {
        $storage->{$key} = $hash{$key};
    }
    return $obj;
}

sub STORE {
    my( $self, $key, $val ) = @_;
    $Yote::Obj::__OBJ_PROVIDER->dirty( $self->[2], $self->[0] );
    $self->[1]{$key} = $Yote::Obj::__OBJ_PROVIDER->xform_in( $val );
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
    return $Yote::Obj::__OBJ_PROVIDER->xform_out( $self->[1]{$key} );
}

sub EXISTS {
    my( $self, $key ) = @_;
    return defined( $self->[1]{$key} );
}
sub DELETE {
    my( $self, $key ) = @_;
    $Yote::Obj::__OBJ_PROVIDER->dirty( $self->[2], $self->[0]);
    return delete $self->[1]{$key};
}
sub CLEAR {
    my $self = shift;
    $Yote::Obj::__OBJ_PROVIDER->dirty( $self->[2], $self->[0] );
    %{$self->[1]} = ();
}

package Yote::YoteDB;

use strict;
use warnings;

no warnings 'uninitialized';

use Yote::IO::FixedStore;
use Yote::IO::StoreManager;

use WeakRef;
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
  my( $pkg, $obj_provider, $args ) = @_;
  my $class = ref( $pkg ) || $pkg;
  make_path( $args->{ store } );
  my $filename = "$args->{ store }/OBJ_INDEX";
  # LII template is a long ( for object id, then the table id, then the index in that table
  return bless {
                args          => $args,
                OBJ_INDEX     => new Yote::IO::FixedRecycleStore( "LII", $filename ),
                STORE_MANAGER => new Yote::IO::StoreManager( $args ),
                OBJ_PROVIDER  => $obj_provider,
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
  $ret;
} #fetch

#
# The first object in a yote data store can trace a reference to
# all active objects.
#
sub first_id {
  my $OI = shift->{OBJ_INDEX};
  if ( $OI->entries < 1 ) {
      $OI->next_id;
  }
  return 1;
} #first_id

#
# Create a new object id and return it. Will never return the
# value of first_id
#
sub get_id {
  my $self = shift;
  my $x = $self->{OBJ_INDEX}->next_id;
  if( $x == $self->first_id() ) {
      return $self->get_id;
  }
  return $x;
} #get_id


sub max_id {
  return shift->{OBJ_INDEX}->entries;
}


sub get_recycled_ids {
  return shift->{OBJ_INDEX}->get_recycled_ids;
}

sub recycle_objects {
  my $self = shift;

  my $mark_to_keep_store = new Yote::IO::FixedStore( "I", $self->{args}{store} . '/RECYCLE' );
  $mark_to_keep_store->ensure_entry_count( $self->{OBJ_INDEX}->entries );
  
  # the already deleted cannot be re-recycled
  my $ri = $self->{OBJ_INDEX}->get_recycled_ids;
  for ( @$ri ) {
    $mark_to_keep_store->put_record( $_, [ 1 ] );
  }

  my $keep_id = $self->first_id;
  my( @queue ) = ( $keep_id );

  $mark_to_keep_store->put_record( $keep_id, [ 1 ] );

  # get the object ids referenced by this keeper object
  while( @queue ) {
    $keep_id = shift @queue;

    my $item = $self->fetch( $keep_id );
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

  # the purge begins here
  my $count = 0;
  my $cands = $self->{OBJ_INDEX}->entries;

  my( %weak_only_check, @weaks, %weaks );
  for my $cand ( 1..$cands) { #iterate each id in the entire object store
    my( $keep ) = $mark_to_keep_store->get_record( $cand )->[0];
    my $wf = $$self->{OBJ_PROVIDER}{__WEAK_REFS}{$cand};
    
    #OKEY, we have to fight cicular references. if an object in weak reference only references other things in
    # weak references, then it can be removed";
    if ( ! $keep ) {
      if( $wf ) {
        push @weaks, [ $cand, $wf ];
      }
      else { #this case is something in the db that is not connected to the root and not loaded anywhere
        ++$count;
        $self->{OBJ_INDEX}->delete( $cand, 1 );
      }
    }
  }
  # check things attached to the weak refs.
  for my $wf (@weaks) { 
    my( $id, $obj ) = @$wf;
    if ( ref( $obj ) eq 'ARRAY' ) { 
      for ( map { $self->{OBJ_PROVIDER}->xform_in($_) } @$obj ) {
        $weak_only_check{ $_ }++;
      }
    } elsif ( ref( $obj ) eq 'HASH' ) {
      for ( map { $self->{OBJ_PROVIDER}->xform_in($_) } values %$obj) {
        $weak_only_check{ $_ }++;
      }
    } else {
      for ( values %{ $obj->{DATA} } ) {
        $weak_only_check{ $_ }++;
      }
    }
  } #each weak
  
  # can delete things with only references to the WEAK and DIRTY caches.
  my( @to_delete );
  for my $weak ( @weaks ) {
    my( $id, $obj ) = @$weak;
    unless( $obj ) {
      push @to_delete, $id;
      ++$count;
    } else {
      my $extra_refs = 2;
      # hash and array have an additional reference in the tie
      if( ref( $obj ) =~ /^(ARRAY|HASH)$/ ) {
        $extra_refs++;
      }
      if( ($extra_refs+$weak_only_check{$id}) >= refcount($obj) ) {
        push @to_delete, $id;
        ++$count;
      }
    }
  }
  for( @to_delete ) {
    $self->{OBJ_INDEX}->delete( $_, 1 );
    delete $$self->{OBJ_PROVIDER}{__WEAK_REFS}{$_};
  }
  
  # remove recycle datastore
  $mark_to_keep_store->unlink_store;
  
  return $count;
  
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

1;
