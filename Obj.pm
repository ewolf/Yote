package GServ::Obj;

#
# A GServ object, mostly just syntactic sugar
#

use strict;

use GServ::ObjProvider;
use Data::Dumper;

sub new {
    my( $pkg, $id ) = @_;
    my $class = ref($pkg) || $pkg;

    my $obj = bless {
        ID       => $id,
        DATA     => {},
    }, $class;

    $obj->{ID} ||= GServ::ObjProvider::get_id( $obj );

    $obj->init;

    return $obj;
} #new

# returns true if the object passsed in is the same as this one.
sub is {
    my( $self, $obj ) = @_;
    return ref( $obj ) && $obj->isa( 'GServ::Obj' ) && $obj->{ID} == $self->{ID};
}

sub init {}

sub save {
    my $self = shift;
    GServ::ObjProvider::stow( $self );
} #save

sub AUTOLOAD {
    my( $s, $arg ) = @_;
    my $func = our $AUTOLOAD;

    if( $func =~/:add_to_(.*)/ ) {
        my( $fld ) = $1;
        my $get = "get_$fld";
        my $arry = $s->$get([]); # init array if need be
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, @vals ) = @_;
            push( @$arry, @vals );
        };
        goto &$AUTOLOAD;

    }
    elsif( $func =~ /:remove_from_(.*)/ ) {
        my $fld = $1;
        my $get = "get_$fld";
        my $arry = $s->$get([]); # init array if need be
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, $val ) = @_;
            my $count = grep { $_ eq $val } @$arry;
            while( $count ) {
                for my $i (0..$#$arry) {
                    if( $arry->[$i] eq $val ) {
                        --$count;
                        splice @$arry, $i, 1;
                        last;
                    }
                }
            }
        };
        goto &$AUTOLOAD;

    }
    elsif ( $func =~ /:set_(.*)/ ) {
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, $val ) = @_;
            my $inval = GServ::ObjProvider::xform_in( $val );
            GServ::ObjProvider::dirty( $self, $self->{ID} ) if $self->{DATA}{$fld} ne $inval;
            $self->{DATA}{$fld} = $inval
        };
        goto &$AUTOLOAD;
    }
    elsif( $func =~ /:get_(.*)/ ) {
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, $init_val ) = @_;
            if( ! defined( $self->{DATA}{$fld} ) && defined($init_val) ) {
                $self->{DATA}{$fld} = GServ::ObjProvider::xform_in( $init_val );
                GServ::ObjProvider::dirty( $self, $self->{ID} );
            }
            print STDERR Data::Dumper->Dump( ["GET $fld ".$self->{DATA}{$fld}] );
            return GServ::ObjProvider::xform_out( $self->{DATA}{$fld} );
        };
        goto &$AUTOLOAD;
    }
    else {
        die "Unknown GServ::Obj function '$func'";
    }

} #AUTOLOAD

sub DESTROY {}

1;
__END__

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
