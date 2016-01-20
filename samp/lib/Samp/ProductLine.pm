package Samp::ProductLine;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

use Samp::Step;

sub _allowedUpdates {
    [ qw( name 
          notes
          food_cost
          sale_price
       ) ]
}

sub _lists {
    { steps     => 'Samp::Step',
      ingredients => 'Samp::ProductLine',
    };
}


#
# avg hours in month? est 52 weeks
# 52*40/12 --> 173 hours/month
# 
#

sub calculate {
    my $self = shift;

    my $work_hours_in_month = 173; #rounded down
    my $work_days_in_month = 21; #rounded down


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
    for my $step (@$steps) {
        my $step_rate = $step->get_production_rate();
        if( $step_rate ) {
            $hours += $slowest_rate / $step_rate; # items / (items/hour)  --> hours
        }
    }
    if( $hours ) {
        my $rate = $slowest_rate / $hours;
        $self->set_production_rate( sprintf( "%.2f", $rate ) );
        # how much can be made in a day (8 hours), then in a month!
        $self->set_produced_in_day( sprintf( "%.0f", $rate * 8 ) );
        $self->set_produced_in_month( sprintf( "%.0f",$rate * $work_hours_in_month ) );
    } else {
        $self->set_production_rate( 'n/a' );
        $self->set_produced_in_day( 'n/a' );
        $self->set_produced_in_month( 'n/a' );
    }
      
}

1;

__END__
