package Samp::ProductLine;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Samp::Component';

use Samp::Step;

sub allowedUpdates {
    [ qw( name description units_produced hours food_cost
        sale_price packaging_cost
       ) ]
}

sub lists {
    { steps     => 'Samp::Step' } ,
}

#
# avg hours in month? est 52 weeks
# 52*40/12 --> 173 hours/month
#

sub calc {
    my $self = shift;
    my $work_hours_in_month = 173;

    # find monthly costs
    
    
    # loop thru all steps to find the bottleneck
}

sub calculate {
    my $self = shift;

    my $steps = $self->get_steps([]);
    
    my $rate;
    for my $step (@$steps) {
        my $step_rate = $step->get_production_rate();
        $rate //= $step_rate;
        $rate = $step_rate < $rate ? $step_rate : $rate;
    }

    $self->set_production_rate( $rate );


    my( $slowest_rate, $bottleneck );
    for my $step (@$steps) {
        my $step_rate = $step->get_production_rate();
        $slowest_rate //= $step_rate;
        $bottleneck //= $step;
        if( $step_rate < $slowest_rate ) {
            $slowest_rate =  $step_rate;
            $bottleneck = $step;
        }
    } 
        
    # rate is per hour. Calculate how long it would take
    # to do a production run of X
    my $hours = 0;
    for my $line (@$lines) {
        my $line_rate = $line->get_production_rate();
        if( $line_rate ) {
            $hours += $slowest_rate / $line_rate; # items / (items/hour)  --> hours
        }
    }
    $self->set_production_rate( $slowest_rate / $hours ) if $hours;
}

1;

__END__
