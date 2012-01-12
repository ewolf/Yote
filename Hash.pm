package GServ::Hash;

use strict;

use Tie::Hash;

use Data::Dumper;
use GServ::ObjProvider;

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
    GServ::ObjProvider::dirty( $self, $self->[0] );
    $self->[1]{$key} = GServ::ObjProvider::xform_in( $val );
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
    return GServ::ObjProvider::xform_out( $self->[1]{$key} );
}

sub EXISTS {
    my( $self, $key ) = @_;
    return defined( $self->[1]{$key} );
}
sub DELETE {
    my( $self, $key ) = @_;
    GServ::ObjProvider::dirty( $self, $self->[0]);
    return delete $self->[1]{$key};
}
sub CLEAR {
    my $self = shift;
    GServ::ObjProvider::dirty( $self, $self->[0] );
    for my $key (%{$self->[1]}) {
        delete $self->[1]{$key};
    }
}

1;
__END__


=head1 NAME

GServ::Hash - All hashes in the GServ system get tied to this class.

=head1 DESCRIPTION

GServ::Hash extends Tie::Hash and is used by the GServ system for hash persistance.

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
