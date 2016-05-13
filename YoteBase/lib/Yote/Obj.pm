package Yote::Obj;

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
    $obj->_init(); #called the first time the object is created.
    $obj_store->_dirty( $obj, $obj->{ID} );

    if( ref( $data ) eq 'HASH' ) {
        $obj->absorb( $data );
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

sub DESTROY {}

1;
