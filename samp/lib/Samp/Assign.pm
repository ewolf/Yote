package Samp::Assign;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _allowedUpdates {
    qw(
        notes

        item
        use_quantity
      )
} #allowedUpdates

sub _calculate {
    my $self = shift;

    $self->get_attached_to->_calculate( 'assign', $self );
    $self->get_item->_calculate( 'assign', $self );
}

sub _gather {
    my( $self, $seen ) = @_;
    my( $item, $attached ) = ( $self->get_item, $self->get_attached_to );
    $item, $attached, $item->gather( $seen ), $attached->gather( $seen );
}

1;

__END__
