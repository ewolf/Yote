package Samp::Employee;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _allowedUpdates {
    [ qw(
        name 
        notes
        hourly_pay
        hours_per_week
      ) ]
} #allowedUpdates

sub _when_added {
    my( $self, $toObj, $listName, $moreArgs ) = @_;
#    $self->add_to_products_worked_on( $toObj );
}
sub _when_removed {
    my( $self, $fromObj, $listName, $moreArgs ) = @_;
#    $self->remove_from_products_worked_on( $toObj );
}

sub calculate {
    my $self = shift;
    my $scene = $self->get_parent;
    $scene->calculate;
}

1;
