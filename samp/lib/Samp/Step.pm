package Samp::Step;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _allowedUpdates {
    [ qw(
        name 
        notes

        produced_in_run
        run_minutes
        min_run_time

        employees_required 
        overhead_cost_per_run
        overhead_cost_per_hour
      ) ]
} #allowedUpdates

sub _lists {
    { 
        employees       => 'Samp::Employee',
    };
}

sub _init {
    my $self = shift;
    $self->SUPER::_init;
    $self->set_is_bottleneck(0);
}

sub run_time {
    my( $self, $quan ) = @_;
    my $min  = $self->get_min_run_time;
    my $rate = $self->get_production_rate;
    return $min unless $rate;
    my $time = $quan / $rate;
    return $min > $time ? $min : $time;
}

sub employees {
    my $self = shift;
    my $prodline = $self->get_parent;
    my $scene = $prodline->get_parent;

    my %my_emps  = map  { $_->{ID} => $_ } @{$self->get_employees([])};
    
    return grep { ! $my_emps{$_->{ID}} } @{$scene->get_employees};

} #employees

sub calculate {
    my $self = shift;
    my $hours = $self->get_run_minutes() / 60;
    if( $hours > 0 ) {
        my $rate =  $self->get_produced_in_run() / $hours ;
        $self->set_production_rate( $rate );                             # ***** VARSET *****
        $self->set_yield( $rate - $rate * $self->get_failure_rate/100 ); # ***** VARSET *****
    } else { 
        $self->set_yield( 0 );
        $self->set_production_rate(0);
    }
    $self->get_parent()->calculate();
} #calculate 

1;
