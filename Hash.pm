package GServ::Hash;

use strict;

use Tie::Hash;

use Data::Dumper;
use GServ::ObjProvider;

sub TIEHASH {
    my( $class, %hash ) = @_;
    my $id = $hash{__ID__};
    my $storage = bless { __ID__ => $hash{__ID__} }, $class;
    for my $key (grep { $_ ne '__ID__' } keys %hash) {
        $storage->{$key} = GServ::ObjProvider::xform_in($hash{$key});
    }
    return $storage;
}

sub STORE {
    my( $self, $key, $val ) = @_;
    GServ::ObjProvider::dirty( $self, $self->{__ID__} );
    $self->{$key} = GServ::ObjProvider::xform_in( $val );
}

sub FIRSTKEY { 
    my $self = shift;
    my $a = scalar keys %$self;
    my( $k, $val ) = each %$self;
    if( $k ne '__ID__' ) {
        return wantarray ? ( $k => $val ) : $k;
    } 
    ( $k, $val ) = each %$self;
    return wantarray ? ( $k => $val ) : $k;
}
sub NEXTKEY  { 
    my $self = shift;
    my( $k, $val ) = each %$self;
    if( $k ne '__ID__' ) {
        return wantarray ? ( $k => $val ) : $k;
    } 
    ( $k, $val ) = each %$self;
    return wantarray ? ( $k => $val ) : $k;
}

sub FETCH {
    my( $self, $key ) = @_;
    return $self->{$key} if $key eq '__ID__';
    return GServ::ObjProvider::xform_out( $self->{$key} );
}

sub EXISTS {
    my( $self, $key ) = @_;
    return defined( $self->{$key} );
}
sub DELETE {
    my( $self, $key ) = @_;
    GServ::ObjProvider::dirty( $self, $self->{__ID__} );
    return delete $self->{$key};
}
sub CLEAR {
    my $self = shift;
    GServ::ObjProvider::dirty( $self, $self->{__ID__} );
    for my $key (%$self) {
        delete $self->{$key};
    }
}

1;
__END__

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
