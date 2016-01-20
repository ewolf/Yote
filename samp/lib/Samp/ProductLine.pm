package Samp::ProductLine;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

use Samp::Step;
use Samp::Ingredient;

sub _allowedUpdates {
    [ qw( name 
          notes
          cost_per_batch
          sale_price
          expected_sales
          expected_sales_per
       ) ]
}

sub _lists {
    { steps       => 'Samp::Step',
      ingredients => 'Samp::Ingredient', #TODO - maybe this should be a hash?
    };
}

sub monthly_units_needed_for_ingredient {
    my( $self, $prod ) = @_;
    my $ings = $self->get_ingredients([]);
    my $count = 0;
    for my $ing ( @$ings ) {
        if( $prod == $ing->get_product ) {
            $count += $ing->amount_per_run;
        }
    }
    return $count;
}

sub choices {
    my( $self, $field ) = @_;
    if( $field eq 'ingreds' ) {
        my $scene = $self->get_parent;
        return ( ['', "choose ingredient"], grep { $_ ne $self } @{$scene->get_product_lines} );
    } elsif( $field eq 'expected_sales_per' ) {
        return (qw( day week month year ));
    }
    return ();
} #choices

sub c2 {
    # calculate redux
    my $self = shift;

    # find the following :
    #    total cost per item 
    #      labor cost per item ( includes cost to make ingredients )
    #      food cost per item
    #      packaging cost per item
    #
    #    profit per item
    #      labor cost percentage
    #      food cost percentage
    #      packaging cost percentage
    #
    #    batches required per month
    #    items produced per month
    #    production rate per hour
    #    time(hours) per batch
    #    batch size
    #
    
} #c2

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

    $self->set_hourly_production_rate( $rate );

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
    my $hours_per_batch = 0;
    for my $step (@$steps) {
        my $step_rate = $step->get_production_rate();
        if( $step_rate ) {
            $hours_per_batch += $slowest_rate / $step_rate; # items / (items/hour)  --> hours
        }
    }

    # so percentage that each step takes in the process
    
    if( $hours_per_batch ) {
        my $rate = $slowest_rate / $hours_per_batch;

        for my $step (@$steps) {
            my $perc = $step->get_production_rate / $rate;
            $step->set_prod_time_percentage( $perc );
        }
        
        $self->set_production_rate( $rate ); #rate per hour
        # how much can be made in a day (8 hours), then in a month!
        $self->set_produced_in_day( $rate * 8 );
        $self->set_produced_in_month( $rate * $work_hours_in_month );
    } else {
        $self->set_production_rate( 'n/a' );
        $self->set_produced_in_day( 'n/a' );
        $self->set_produced_in_month( 'n/a' );
    }

    my %times = (  #normalize to month
                   day => 21,
                   week => 52.0/12,
                   month => 1,
                   year  => 1.0/12,
        );
    my $needed_in_month = $self->get_expected_sales * $times{ $self->get_expected_sales_per };
    
    # check to see how much products that this is an ingredient for need
    my $ingredsOf = $self->get_ingredient_of( [] );
    for my $prod (@$ingredsOf) {
        # see how many batches of it are needed
        $needed_in_month += $prod->monthly_units_needed_for_ingredient( $self );
    }
    
    my $needed_in_hour    = $needed_in_month / $work_hours_in_month;
    my $prod_hours_needed = $needed_in_hour / $self->get_production_rate;    
    my $batches_needed    = $prod_hours_needed / $hours_per_batch;

    # ceil the batches needed
    $batches_needed = int($batches_needed) == $batches_needed ? $batches_needed : 1 + int($batches_needed);
    $self->set_monthly_batches_needed( $batches_needed );

    # recalculate prod hours needed due to quantized batch size
    $prod_hours_needed = $batches_needed * $hours_per_batch;

    $self->set_monthly_prod_hours( $prod_hours_needed );

    # now how much labor is needed in man hours?
    my $labor_hours = 0;
    for my $step (@$steps) {
        $labor_hours += $prod_hours_needed * $step->get_prod_time_percentage * $step->get_employees_required;
    }
    
    $self->set_monthly_labor_hours( $labor_hours );

    # how much food cost is there per batch
    my $scene = $self->get_parent;
    my $employee_rate = $scene->get_employee_monthly_cost;
    my $monthly_labor_cost = $employee_rate * $labor_hours;


    # cost of ingredients
    my $cost_per_month = $self->get_cost_per_batch;
    my $ings = $self->get_ingredients([]);
    for my $ing (@$ings) {
        
    }

    # calculate full cost per batch then cost per item, and propogate down how many
    # batches are needed given the current configuarion.
    # start with those things which are sold ( have sale price ), then gather ingredients
    # check for circular loops though
    
    $self->set_monthly_labor_cost( $monthly_labor_cost );
    my $expected_monthly_revenue = $sold_in_month * $self->get_sale_price;

    $self->set_monthly_revenue( $expected_monthly_revenue );
    
    
} #calculate

1;

__END__
