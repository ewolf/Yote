package Yote::Array;

use strict;
use warnings;

use Tie::Array;

use vars qw($VERSION);

$VERSION = '0.01';

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
    return Yote::ObjProvider::xform_out ( $self->[1][$idx] );
}

sub FETCHSIZE {
    my $self = shift;
    return scalar(@{$self->[1]});
}

sub STORE {
    my( $self, $idx, $val ) = @_;
    Yote::ObjProvider::dirty( $self->[2], $self->[0] );
    $self->[1][$idx] = Yote::ObjProvider::xform_in( $val );
}
sub STORESIZE {}  #stub for array

sub EXISTS {
    my( $self, $idx ) = @_;
    return defined( $self->[1][$idx] );
}
sub DELETE {
    my( $self, $idx ) = @_;
    Yote::ObjProvider::dirty( $self->[2], $self->[0] );
    delete $self->[1][$idx];
}

sub CLEAR {
    my $self = shift;
    Yote::ObjProvider::dirty( $self->[2], $self->[0] );
    @{$self->[1]} = ();
}
sub PUSH {
    my( $self, @vals ) = @_;
    Yote::ObjProvider::dirty( $self->[2], $self->[0] );
    push( @{$self->[1]}, map { Yote::ObjProvider::xform_in($_) } @vals );
}
sub POP {
    my $self = shift;
    Yote::ObjProvider::dirty( $self->[2], $self->[0] );
    return Yote::ObjProvider::xform_out( pop @{$self->[1]} );
}
sub SHIFT {
    my( $self ) = @_;
    Yote::ObjProvider::dirty( $self->[2], $self->[0] );
    my $val = splice @{$self->[1]}, 0, 1;
    return Yote::ObjProvider::xform_out( $val );
}
sub UNSHIFT {
    my( $self, @vals ) = @_;
    Yote::ObjProvider::dirty( $self->[2], $self->[0] );
    unshift @{$self->[1]}, map {Yote::ObjProvider::xform_in($_)} @vals;
}
sub SPLICE {
    my( $self, $offset, $length, @vals ) = @_;
    Yote::ObjProvider::dirty( $self->[2], $self->[0] );
    return map { Yote::ObjProvider::xform_out($_) } splice @{$self->[1]}, $offset, $length, map {Yote::ObjProvider::xform_in($_)} @vals;
}
sub EXTEND {}

sub DESTROY {}

1;
__END__


=head1 NAME

Yote::Array - All arrays in the Yote system get tied to this class.

=head1 DESCRIPTION

This module is essentially a private module and its methods will not be called directly by programs.
Yote::Array extends Tie::Array and is used by the Yote system for array persistance.
This is used transparently and this can be considered a private class.

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
