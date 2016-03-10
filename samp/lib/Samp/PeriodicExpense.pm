package Samp::PeriodicExpense;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _gather { shift->get_cost_period_types }

sub _init {
    my $self = shift;
    $self->SUPER::_init;
    $self->set_cost_period( 'month' );
    $self->set_cost_period_types( [qw( month quarter year )] );
}

sub _allowedUpdates {
    qw(
        name 
        notes
        cost
        cost_period
      )
} #allowedUpdates

my %times = (  #normalize to month
               day => 21,
               week => 52.0/12,
               month => 1,
               year  => 1.0/12,
    );

sub calculate {
    my $self = shift;
    $self->set_monthly_expense( $self->get_cost * $times{$self->get_cost_period} );
    $self->get_parent->calculate( 'expense' );
}

1;
