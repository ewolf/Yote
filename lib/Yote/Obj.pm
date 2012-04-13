package Yote::Obj;

#
# This is base Yote Object class. 
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

use strict;

use Yote::ObjProvider;

use vars qw($VERSION);

$VERSION = '0.01';

sub new {
    my( $pkg, $id ) = @_;
    my $class = ref($pkg) || $pkg;

    my $obj = bless {
        ID       => $id,
        DATA     => {},
    }, $class;

    my $needs_init = ! $obj->{ID};

    $obj->{ID} ||= Yote::ObjProvider::get_id( $obj );
    $obj->init() if $needs_init;

    return $obj;
} #new

#
# Called the very first time this object is created. It is not called
# when object is loaded from storage.
# 
sub init {}

#
# Updates the object but only for capitolized keys that already exist.
# public client method.
#
sub update {
    my( $self, $data, $account ) = @_;
    my $updated = {};
    for my $fld (keys %$data) {
        next unless $fld =~ /^[A-Z]/ && defined( $self->{$fld} );
        my $inval = Yote::ObjProvider::xform_in( $data->{$fld} );
        Yote::ObjProvider::dirty( $self, $self->{ID} ) if $self->{DATA}{$fld} ne $inval;
        $self->{DATA}{$fld} = $inval;
        $updated->{$fld} = $inval;
    }
    return $updated;
} #update

sub rekey {
    my( $self, $data, $account ) = @_;
    my( $from, $to ) = ( $data->{from}, $data->{to} );
    if( $self->{DATA}{$to} ) {
	die "Keyname '$to' already taken";
    }
    $self->{DATA}{$to} = $self->{DATA}{$from};
    delete $self->{DATA}{$from};
    return 1;
} #rekey

sub load_direct_descendents {
    my( $self, $data, $account ) = @_;
    my @ret;
    for my $fld (grep { $_ !~ /^_/ } keys %{$self->{DATA}}) {
        my $val = $self->{DATA}{$fld};
        next unless $val > 0;
        push( @ret, Yote::ObjProvider::xform_out( $val ) );
    }
    return \@ret;
} #load_direct_descendents 

#
# Transforms data structure but does not assign ids to non tied references.
#
sub _transform_data_no_id {
    my( $self, $item, $acct ) = @_;
    if( ref( $item ) eq 'ARRAY' ) {
        my $tied = tied @$item;
        if( $tied ) {
            return Yote::ObjProvider::get_id( $item ); 
        }
        return [map { $self->_obj_to_response( $_, $acct, 1 ) } @$item];
    }
    elsif( ref( $item ) eq 'HASH' ) {
        my $tied = tied %$item;
        if( $tied ) {
            return Yote::ObjProvider::get_id( $item ); 
        }
        return { map { $_ => $self->_obj_to_response( $item->{$_}, $acct, 1 ) } keys %$item };
    }
    elsif( ref( $item ) ) {
        return  Yote::ObjProvider::get_id( $item ); 
    }
    else {
        return "v$item"; #scalar case
    }
} #_transform_data_no_id

#
# Converts scalar, yote object, hash or array to data for returning.
#
sub _obj_to_response {
    my( $self, $to_convert, $acct, $xform_out ) = @_;
    my $ref = ref($to_convert);
    my $use_id;
    if( $ref ) {
        my( $m, $d ) = ([]);
        if( $ref eq 'ARRAY' ) {
            my $tied = tied @$to_convert;
            if( $tied ) {
                $d = $tied->[1];
                $use_id = Yote::ObjProvider::get_id( $to_convert );
                if( $acct ) {
                    $acct->get_login()->get__allowed_access()->{$use_id} = 1;
                }
                return $use_id unless $xform_out;
            } else {
                $d = $self->_transform_data_no_id( $to_convert, $acct );
            }
        } 
        elsif( $ref eq 'HASH' ) {
            my $tied = tied %$to_convert;
            if( $tied ) {
                $d = $tied->[1];
                $use_id = Yote::ObjProvider::get_id( $to_convert );
                if( $acct ) {
                    $acct->get_login()->get__allowed_access()->{$use_id} = 1;
                }
                return $use_id unless $xform_out;
            } else {
                $d = $self->_transform_data_no_id( $to_convert, $acct );
            }
        } 
        else {
            $use_id = Yote::ObjProvider::get_id( $to_convert );
            if( $acct ) {
                $acct->get_login()->get__allowed_access()->{$use_id} = 1;
            }
            return $use_id unless $xform_out;
            $d = { map { $_ => $to_convert->{DATA}{$_} } grep { $_ && $_ !~ /^_/ } keys %{$to_convert->{DATA}}};

            $m = Yote::ObjProvider::package_methods( $ref );
        }
        return { a => ref( $self ), c => $ref, id => $use_id, d => $d, 'm' => $m };
    } # if a reference
    return "v$to_convert" if $xform_out;
    return $to_convert;
} #_obj_to_response


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
        Yote::ObjProvider::get_id( $obj ) == Yote::ObjProvider::get_id( $self );
}

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
            if( ref( $arry ) eq 'Yote::Array' ) {
                $arry->PUSH( @vals );
            } else {
                push( @$arry, @vals );
            }
        };
        use strict 'refs';
        goto &$AUTOLOAD;

    }
    elsif( $func =~ /:remove_from_(.*)/ ) { #removes the first instance of the target thing from the list
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, $val ) = @_;
            my $get = "get_$fld";
            my $arry = $self->$get([]); # init array if need be
            my $count = grep { $_ eq $val } @$arry;
            while( $count ) {
                for my $i (0..$#$arry) {
                    if( $arry->[$i] eq $val ) {
                        --$count;
                        if( ref( $arry ) eq 'Yote::Array' ) {
                            $arry->SPLICE( $i, 1 );
                        } else {
                            splice @$arry, $i, 1;
                        }
                        last;
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

Yote::Obj is a container class with hooks into the persistance engine. It has few methods, but dynamically autoloads and installed getters and setters as needed. This class is meant to be overridden by application objects, though it needs no modification to be a perfectly functional container class.

=head2 PUBLIC METHODS

=over 4

=item new

The new method takes no arguments. Any object created with new automatically gets assigned an ID and init is called only once before the object is saved in the data store.

=item init

This is a stub method meant to be overridden by subclasses.

=item is

Returns true if the object passed in is equivalent to this one. Note that only one instance of an individual object will be present at a time in the application server.

=item save

Takes no arguments and causes this object to be written into the datastore. This is automatically called by the application server.

=back

=head2 AUTOLOADED METHODS

=over 4

=item get_foo(initilizing_value)

Returns the value of foo where foo can be any string. This may take a single argument such that if foo is undefined in the object, it will be set to the initial argument. This may return an array reference, hash reference, Yote::Obj or scalar.

=item set_foo(item)

Sets the value of foo to the given argument, which may be an array reference, hash reference, Yote::Obj or scalar.

=item add_to_bar(item)

Ads the item to the list bar. If bar does not exist, it is created as a list. If it exists and is not a list, an error will be thrown.

=item remove_from_list(item)

Removes the item from the list bar. If bar does not exist, it is created as a list. If it exists and is not a list, an error will be thrown.

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
