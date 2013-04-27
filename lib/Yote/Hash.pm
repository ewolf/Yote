package Yote::Hash;

use strict;
use warnings;

no warnings 'uninitialized';

use Tie::Hash;

use Yote::ObjProvider;

use vars qw($VERSION);

$VERSION = '0.01';

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
    Yote::ObjProvider::dirty( $self->[2], $self->[0] );
    $self->[1]{$key} = Yote::ObjProvider::xform_in( $val );
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
    return Yote::ObjProvider::xform_out( $self->[1]{$key} );
}

sub EXISTS {
    my( $self, $key ) = @_;
    return defined( $self->[1]{$key} );
}
sub DELETE {
    my( $self, $key ) = @_;
    Yote::ObjProvider::dirty( $self->[2], $self->[0]);
    return delete $self->[1]{$key};
}
sub CLEAR {
    my $self = shift;
    Yote::ObjProvider::dirty( $self->[2], $self->[0] );
    %{$self->[1]} = ();
}

1;
__END__


=head1 NAME

Yote::Hash - All hashes in the Yote system get tied to this class.

=head1 DESCRIPTION

This module is essentially a private module and its methods will not be called directly by programs.
Yote::Hash extends Tie::Hash and is used by the Yote for hash persistance.
This is used transparently and this can be considered a private class.

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
