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

1;
