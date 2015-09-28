package Yote;

use strict;
use warnings;
no  warnings 'uninitialized';

use vars qw($VERSION);

$VERSION = '1.0';

use DB::DataStore;

=head1 NAME

Yote - Persistant Perl container objects in a directed graph
       of lazilly loaded nodes.

=head1 SYNOPSIS
 
 use Yote;

 my $store = Yote::open_store( '/path/to/data-directory' );

 my $root_node = $store->fetch_root;

 $root_node->add_to_myList( $store->newobj( { 
    someval  => 123.53,
    somehash => { A => 1 },
    someobj  => $store->newobj( { foo => "Bar" } );
 } );
 # the root node now has a list 'myList' attached to it with the single 
 # value of a yote object that yote object has two fields, 
 # one of which is an other yote object.
 
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

 my $someid = $root_node->get_someobj->{ID};

 my $someref = $store->fetch( $someid );

 $myList->[0]->set_condition( "About to be recycled" );
 delete $myList->[0];

 $store->stow_all;
 $store->run_recycler;

=head1 PUBLIC METHODS

=cut


=head2 open_store( '/path/to/directory' )

Starts up a persistance engine with the arguments passed in.
This must be called before any use of t
   
=cut
$Yote::STORES = {};
sub open_store {
    my $path = pop;
    $Yote::STORES->{$path} ||= Yote::ObjStore->_new( { store => $path } );
    $Yote::STORES->{$path};
}


# ---------------------------------------------------------------------------------------------------------------------

package Yote::Obj;

use strict;
use warnings;
no warnings 'uninitialized';

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


sub _new { #new Yote::Obj
    my( $pkg, $obj_store, $data, $_id ) = @_;

    my $class = ref($pkg) || $pkg;
    my $obj = bless {
        DATA     => {},
        STORE    => $obj_store,
    }, $class;
    $obj->{ID} = $_id || $obj_store->_get_id( $obj );
    $obj->_init(); #called the first time the object is created.
    $obj_store->_dirty( $obj, $obj->{ID} );

    if( ref( $data ) eq 'HASH' ) {
        for my $key ( sort keys %$data ) {
            $obj->{DATA}{$key} = $obj_store->_xform_in( $data->{ $key } );
        }
        $obj_store->_dirty( $obj, $obj->{ID} );
    } elsif( $data ) {
        die "Yote::Obj::new must be called with hash or undef. Was called with '". ref( $data ) . "'";
    }
    return $obj;
} #_new


#
# Called by the object provider; returns a Yote::Obj the object
# provider will stuff data into. Takes the class and id as arguments.
#
sub _instantiate {
    bless { ID => $_[1], DATA => {}, STORE => $_[2] }, $_[0];
} #_instantiate


# ---------------------------------------------------------------------------------------------------------------------

package Yote::ObjStore;

use strict;
use warnings;
no warnings 'numeric';
no warnings 'uninitialized';
no warnings 'recursion';

use Crypt::Passwd::XS;
use WeakRef;


use vars qw($VERSION);

$VERSION = '0.073';

=head1 NAME

Yote::ObjStore

=head1 SYNOPSIS


=cut

# ------------------------------------------------------------------------------------------
#      * PUBLIC CLASS METHODS *
# ------------------------------------------------------------------------------------------

=head2 fetch_root

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

=head2 newobj( { ... data .... } )

 Creates a new data object initialized with the incoming hash ref data.
 Once created, the object will be saved in the data store when 
 Yote::Obj::stow_all has been called.  If the object is not attached 
 to the root or an object that can be reached by the root, it will be 
 recycled when Yote::Obj::recycle_objects is called.

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


=head2 fetch




=cut
sub fetch {
    my( $self, $id ) = @_;
    return undef unless $id;
    #
    # Return the object if we have a reference to its dirty state.
    #
    my $ref = $self->{_DIRTY}->{$id} || $self->{_WEAK_REFS}->{$id};

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
            $class =~ /^Yote::(Root|Obj)/ || eval("require $class");
            return undef if $@;

            my $obj = $class->_instantiate( $id, $self );
            $obj->{DATA} = $data;
            $obj->{ID} = $id;
            $obj->_load();
            $self->_store_weak( $id, \$obj );
            return $obj;
        }
    }

    return undef;
} #fetch

sub run_recycler {
    my $self = shift;
    $self->stow_all();
    $self->{_DATASTORE}->_recycle_objects();
} #run_recycler

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


# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------
sub _new { #Yote::ObjStore
    my( $pkg, $args ) = @_;
    my $self = bless {
        _DIRTY     => {},
        _WEAK_REFS => {},
    }, $_[0];
    $self->{_DATASTORE} = Yote::YoteDB->open( $self, $args );
    $self->fetch_root;
    $self->stow_all;
    $self;
} #_new


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
    if( $class eq 'Yote::Array') {
        return $ref->[0];
    }
    elsif( $class eq 'ARRAY' ) {
        my $tied = tied @$ref;
        if( $tied ) {
            $tied->[0] ||= $self->{_DATASTORE}->_get_id( "ARRAY" );
            $self->_store_weak( $tied->[0], \$ref );
            return $tied->[0];
        }
        my( @data ) = @$ref;
        my $id = $self->{_DATASTORE}->_get_id( $class );
        tie @$ref, 'Yote::Array', $self, $id;
        $tied = tied @$ref; $tied->[3] = $ref;
        push( @$ref, @data );
        $self->_dirty( $ref, $id );
        $self->_store_weak( $id, \$ref );
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
            $self->_store_weak( $tied->[0], \$ref );
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
        $self->_store_weak( $id, \$ref );
        return $id;
    }
    else {
        return $ref->{ID} if $ref->{ID};
        if( $class eq 'Yote::Root' ) {
            $ref->{ID} = $self->{_DATASTORE}->_first_id( $class );
        } else {
            $ref->{ID} ||= $self->{_DATASTORE}->_get_id( $class );
        }
        $self->_store_weak( $ref->{ID}, \$ref );

        return $ref->{ID};
    }

} #_get_id

sub _stow {
    my( $self, $obj ) = @_;

    my $class = ref( $obj );
    return unless $class;
    my $id = $self->_get_id( $obj );
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
} #_stow

sub _xform_in {
    my( $self, $val ) = @_;
    if( ref( $val ) ) {
        return $self->_get_id( $val );
    }
    return "v$val";
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
    return $self->{_DIRTY}{$id};
} #_is_dirty

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
    my( $class, $obj_store, $id, @list ) = @_;
    my $storage = [];

    # once the array is tied, an additional data field will be added
    # so obj will be [ $id, $storage, $obj_store, $data ]
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

use vars qw($VERSION);

$VERSION = '0.02';

sub TIEHASH {
    my( $class, $obj_store, $id, %hash ) = @_;
    my $storage = {};
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

# ---------------------------------------------------------------------------------------------------------------------

package Yote::YoteDB;

use strict;
use warnings;

no warnings 'uninitialized';

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
sub open {
  my( $pkg, $obj_store, $args ) = @_;
  my $class = ref( $pkg ) || $pkg;

  my $self = bless {
      args          => $args,
      OBJ_STORE  => $obj_store,
      DATA_STORE => DB::DataStore->open( $args->{ store } ),
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

# used for debugging and testing
sub _get_recycled_ids {
  shift->{DATA_STORE}->_get_recycled_ids;
}

sub _recycle_objects {
  my $self = shift;

  my $mark_to_keep_store = DB::DataStore::FixedStore->open( "I", $self->{args}{store} . '/RECYCLE' );
  $mark_to_keep_store->ensure_entry_count( $self->{DATA_STORE}->entry_count );
  
  # the already deleted cannot be re-recycled
  my $ri = $self->{DATA_STORE}->_get_recycled_ids;
  print STDERR Data::Dumper->Dump([$ri,"RECYCLED IDS"]);
  for ( @$ri ) {
    $mark_to_keep_store->put_record( $_, [ 1 ] );
  }

  my $keep_id = $self->_first_id;
  my( @queue ) = ( $keep_id );

      print STDERR Data::Dumper->Dump(["MARKING $keep_id"]);
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
      print STDERR Data::Dumper->Dump(["MARKING $keeper"]);
      push @queue, $keeper;
    }
  } #while there is a queue

  # the purge begins here
  my $cands = $self->{DATA_STORE}->entry_count;

  my( %to_recycle, %weak_ref_check );
  for my $cand ( 1..$cands) { #iterate each id in the entire object store
    my( $keep ) = $mark_to_keep_store->get_record( $cand )->[0];
    my $wf = $self->{OBJ_STORE}{_WEAK_REFS}{$cand};

    if ( ! $keep ) {
      if( $wf ) {
          $weak_ref_check{ $cand } = $wf;
      }
      else {
          $to_recycle{ $cand } = 1;
      }
    }
  }

  # weak references will not be deleted
  # unless they only are referenced by other weak references
  # returns 1 if it should not recycle
  my $recursive_weak_check = sub {
      my( $weak_id, $seen ) = @_;
      return 0 if $seen->{$weak_id}++;

      my $obj = $self->{OBJ_STORE}->_xform_in($weak_id);
      if ( ref( $obj ) eq 'ARRAY' ) { 
          for ( grep { $_ !~ /^v/ } map { $self->{OBJ_STORE}->_xform_in($_) } @$obj ) {
              return 1 if ! $to_recycle{ $_ } or $recursive_weak_check( $_ );
          }
      } elsif ( ref( $obj ) eq 'HASH' ) {
          for ( grep { $_ !~ /^v/ } map { $self->{OBJ_STORE}->_xform_in($_) } values %$obj) {
              return 1 if ! $to_recycle{ $_ } or $recursive_weak_check( $_ );
          }
      } else {
          for ( grep { $_ !~ /^v/ } values %{ $obj->{DATA} } ) {
              return 1 if ! $to_recycle{ $_ } or $recursive_weak_check( $_ );
          }
      }
      return 0;
  }; #recursive weak check

  # check things attached to the weak refs.
  # checking for circular weak references
  for my $wf_id (keys %weak_ref_check) { 
      unless( $recursive_weak_check( $wf_id, $weak_ref_check{$wf_id}, {} ) ) {
          $to_recycle->{$wf_id} = 1;
      }
  }

bla
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
    $self->{DATA_STORE}->recycle( $_, 1 );
    delete $self->{OBJ_STORE}{_WEAK_REFS}{$_};
  }
  
  # remove recycle datastore
  $mark_to_keep_store->unlink_store;
  
  return $count;
  
} #_recycle_objects

#
# Saves the object data for object $id to the data store.
#
sub _stow {
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
