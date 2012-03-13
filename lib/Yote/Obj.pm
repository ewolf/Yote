package Yote::Obj;

#
# A Yote object, mostly just syntactic sugar.
# method names are capitolized to indicate that they are not meant
# as target methods for yote javascript objects.
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
    $obj->_on_load();

    return $obj;
} #new

sub size {
    return scalar keys %{shift->{DATA}};
} #size

#
# Takes the entire key/value pairs of data as field/value pairs attached to this.
#
sub absorb {
    my $self = shift;
    my $data = ref( $_[0] ) ? $_[0] : { @_ };
    for my $fld (keys %$data) {
        my $inval = Yote::ObjProvider::xform_in( $data->{$fld} );
        Yote::ObjProvider::dirty( $self, $self->{ID} ) if $self->{DATA}{$fld} ne $inval;
        $self->{DATA}{$fld} = $inval;
    } #each field
    return undef;
} #absorb


# returns true if the object passsed in is the same as this one.
sub is {
    my( $self, $obj ) = @_;
    return ref( $obj ) && ref( $obj ) eq ref( $self ) &&
        Yote::ObjProvider::get_id( $obj ) == Yote::ObjProvider::get_id( $self );
}

# shallow clones this object
sub clone {
    my $self = shift;
    my $class = ref( $self );
    my $clone = $class->new;
    for my $field (keys %{$self->{DATA}}) {
        $clone->{DATA}{$field} = $self->{DATA}{$field};
    }
    return $clone;
} #clone

#
# Deep clone this object. This will clone any yote object that is not an AppRoot or flagged
# to not deep clone.
# If an object is referenced below itself, the references below it will be set to the 
# reference of the clone. For example, if you have the structure $A = { "foo" =>  $B(NO_DEEP_CLONE), "bar" => [1,2,$A,$C] } 
# and you deep clone A, you will get $Aclone = { "foo" => $B, "bar" => [1,2,$Aclone,$Cclone] }
#
sub _power_clone {
    my( $item, $replacements, $deep_check, $cc ) = @_;
    my $class = ref( $item );

    if( $cc ) {
	$$cc++ ;
    } else {
	$$cc = 0;
    }

    return $item unless $class;

    $replacements ||= {};
    my $id = Yote::ObjProvider::get_id( $item );
    return $replacements->{$id} if $replacements->{$id};

    if( $class eq 'ARRAY' ) {
        my $arry_clone = [ map { _power_clone( $_, $replacements, 1, $cc ) } @$item ];
        Yote::ObjProvider::get_id( $arry_clone );
        $replacements->{$id} = $arry_clone;
        return $arry_clone;
    }
    if( $class eq 'HASH' ) {
        my $hash_clone = { map { $_ => _power_clone( $item->{$_}, $replacements, 1, $cc ) } keys %$item };
        Yote::ObjProvider::get_id( $hash_clone );
        $replacements->{$id} = $hash_clone;
        return $hash_clone;
    }
    return $item if ( $deep_check && $item->{NO_DEEP_CLONE} ) || $item->isa( 'Yote::AppRoot' );
    my $clone = $class->new;
    $replacements->{$item->{ID}} = $clone;

    for my $field (keys %{$item->{DATA}}) {
        my $id_or_val = $item->{DATA}{$field};
        if( $id_or_val > 0 ) { #means its a reference
            my $val = Yote::ObjProvider::xform_out( $id_or_val );
            if( ref( $val ) eq 'ARRAY' ) {
                $clone->{DATA}{$field} = Yote::ObjProvider::xform_in( [map { _power_clone( $_, $replacements, 1, $cc ) } @$val] );
            } elsif( ref( $val ) eq 'HASH' ) {
                $clone->{DATA}{$field} = Yote::ObjProvider::xform_in( {map { $_ => _power_clone( $val->{$_}, $replacements, 1, $cc ) } keys %$val} );
            } else {
		$clone->{DATA}{$field} = Yote::ObjProvider::xform_in( _power_clone( $val, $replacements, 1, $cc ) );
            }
        } else {
            $clone->{DATA}{$field} = $id_or_val;
        }
    }

    unless( $deep_check ) {
	print STDERR "Cloned $$cc items\n"; #print STDERR Data::Dumper->Dump([]);
    }
    return $clone;
    
} #_power_clone

sub init {}
sub _on_load {}

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
