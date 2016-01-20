package Samp::PeriodicExpense;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _init {
    my $self = shift;
    $self->SUPER::_init;
    $self->set_cost_period( 'month' );
}

sub _allowedUpdates {
    [ qw(
        name 
        notes
        cost
        cost_period
      ) ]
} #allowedUpdates

sub cost_period_type {
    return (qw( month quarter year ));
} #cost_period_type



1;
