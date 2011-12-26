package GServ::Array;

use strict;

use Tie::Array;

use Data::Dumper;

use constant {
    OFFSET => 1,
};

sub TIEARRAY {
    my( $class, @list ) = @_;
    my $storage = bless [], $class;
    my( $id, @rest ) = @list;
    push( @$storage, $id );
    for my $item (@rest) {
        push( @$storage, $item );
    }
    return $storage;
}

sub FETCH {
    my( $self, $idx ) = @_;
    return GServ::ObjProvider::xform_out ( $self->[$idx+OFFSET] );
}

sub FETCHSIZE {
    my $self = shift;
    return scalar(@$self) - OFFSET;
}

sub STORE {
    my( $self, $idx, $val ) = @_;
    GServ::ObjProvider::dirty( $self, $self->[0] );
    $self->[$idx+OFFSET] = GServ::ObjProvider::xform_in( $val );
}
sub EXISTS {
    my( $self, $idx ) = @_;
    return defined( $self->[$idx+OFFSET] );
}
sub DELETE {
    my( $self, $idx ) = @_;
    GServ::ObjProvider::dirty( $self, $self->[0] );
    undef $self->[$idx+OFFSET];
}

sub CLEAR {
    my $self = shift;
    GServ::ObjProvider::dirty( $self, $self->[0] );
    splice @$self, 1;
}
sub PUSH {
    my( $self, @vals ) = @_;
    GServ::ObjProvider::dirty( $self, $self->[0] );
    push( @$self, map { GServ::ObjProvider::xform_in($_) } @vals );
}
sub POP {
    my $self = shift;
    GServ::ObjProvider::dirty( $self, $self->[0] );
    if( @$self > OFFSET ) {
        return GServ::ObjProvider::xform_out( pop @$self );
    }
    return undef;
}
sub SHIFT {
    my( $self ) = @_;
    GServ::ObjProvider::dirty( $self, $self->[0] );
    my $val = splice @$self, OFFSET, 1;
    return GServ::ObjProvider::xform_out( $val );
}
sub UNSHIFT {
    my( $self, @vals ) = @_;
    GServ::ObjProvider::dirty( $self, $self->[0] );
    if( @$self > OFFSET ) {
        splice @$self, OFFSET, 0, @vals;
    }
    return undef;
}
sub SPLICE {
    my( $self, $offset, $length, @vals ) = @_;
    GServ::ObjProvider::dirty( $self, $self->[0] );

    my $start = OFFSET + $offset;
    if( $offset < 0 ) {
        my $start = $#$self - $offset;
        if( $start <= OFFSET ) {
            $start = OFFSET;
        }
    }
    splice @$self, $start, $length, @vals;

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
