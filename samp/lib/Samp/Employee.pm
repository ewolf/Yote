package Samp::Employee;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _allowedUpdates {
    qw(
        name 
        notes
        hourly_pay
        hours_per_week
      )
} #allowedUpdates

sub _lists { #steps that this employee performs
    { 
        steps       => 'Samp::Step',
    };
}

sub calculate {
    my $self = shift;

    my $manhours_month = $self->get_hours_per_week * 52.0 / 12;
    $self->set_manhours_month( $manhours_month );
    $self->set_monthly_pay( $self->get_hourly_pay * $manhours_month );

    $self->get_parent->calculate( 'employee', $self );
}

1;
