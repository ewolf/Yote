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

1;
