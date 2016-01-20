package Samp::Step;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _init {
    my $self = shift;
    $self->SUPER::_init();
} #_init


sub _allowedUpdates {
    [ qw(
        name 
        notes

        produced_in_run
        run_hours
        min_run_time

        employees_required 
        overhead_cost_per_run
        overhead_cost_per_hour
      ) ]
} #allowedUpdates

sub run_time {
    my( $self, $quan ) = @_;
    my $min  = $self->get_min_run_time;
    my $rate = $self->get_production_rate;
    return $min unless $rate;
    my $time = $quan / $rate;
    return $min > $time ? $min : $time;
}

sub calculate {
    my $self = shift;
    my $hours = $self->get_run_hours();
    if( $hours > 0 ) {
        $self->set_production_rate( $self->get_produced_in_run() / $hours );
    } else {
        $self->set_production_rate(0);
    }
    $self->get_parent()->calculate();
} #calculate 

1;
