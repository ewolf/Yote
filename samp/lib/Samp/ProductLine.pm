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

          sale_price
          expected_sales
          expected_sales_per

          food_cost_per_batch
          packaging_cost_per_item

          batch_size

          life_as_ingredient
          shelf_life
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

sub expected_sales_per {
    qw( day week month year );
} #expected_sales_per

sub ingredients {
    my $self = shift;
    my $scene = $self->get_parent;
    return ( ['', "choose ingredient"], grep { $_ ne $self } @{$scene->get_product_lines} );
} #ingredients

sub _valid_choice {
    my( $self, $field, $val ) = @_;
    if( $field eq 'expected_sales_per' ) {
        my %c = map { $_ => 1 } @{expected_sales_per()};
        return $c{$val};
    } elsif( $field eq 'ingredients' ) {
        my @ings = $self->ingredients();
        shift @ings;
        my %vals = map { $_->{ID} => 1 } @ings;
        return $vals{$val};
    }
    return 1;
}

sub calculate {
    # calculate redux
    my $self = shift;

    my $work_hours_in_month = 173; #rounded down
    my $work_days_in_month = 21; #rounded down

    # find the following :
    #    total cost per item/batch 
    #      labor cost per item/batch ( includes cost to make ingredients )
    #      food cost per item/batch  ( includes cost to make ingredients )
    #      packaging cost per item/batch ( includes cost to make ingredients )
    #
    #    partial cost per item/batch 
    #      labor cost per item/batch ( excludes cost to make ingredients )
    #      food cost per item/batch  ( excludes cost to make ingredients )
    #      packaging cost per item/batch ( excludes cost to make ingredients )
    #
    #
    #    profit per item/batch
    #      labor cost percentage
    #      food cost percentage
    #      packaging cost percentage
    #
    #    expected monthly revenue/cost/profit ... cost based on number of batches needed
    #
    #    batches required per month based on sales and inventory estimates and shelf life
    #      (expected sales per month )
    #      (items produced per month based on batch size and required batches)
    #
    #    time(hours) per batch  ( does not include cost to make ingredients?
    #    batch size ( if not given )
    #

    my $steps = $self->get_steps([]);

    my( $slowest_rate, $bottleneck, $scaled_run_time );
    for my $step (@$steps) {
        $step->set_is_bottleneck(0);
        my $step_rate = $step->get_production_rate;
        $slowest_rate //= $step_rate;
        $slowest_rate //= $step_rate;
        $bottleneck //= $step;
        if( $step_rate < $slowest_rate ) {
            $slowest_rate =  $step_rate;
            $bottleneck = $step;
        }
    }
    
    #
    # -------------------------- BATCH SIZE ----------------------------------
    #

    $bottleneck->set_is_bottleneck(1) if $bottleneck;

    my $batch_size = $self->get_batch_size || $slowest_rate;

    $self->set_batch_size_used( $batch_size ); #*************
    
    my $run_time = 0;
    for my $step (@$steps) {
        $run_time += $step->run_time( $batch_size );
    }
    return unless $run_time;
    
    #
    # -------------------------- BATCH TIME ----------------------------------
    #


    $self->set_hours_per_batch( $run_time ); #*************

    my %times = (  #normalize to month
                   day => 21,
                   week => 52.0/12,
                   month => 1,
                   year  => 1.0/12,
        );

    my $units_needed_in_month = $self->get_expected_sales * $times{ $self->get_expected_sales_per };

    
    #
    # -------------------------- BATCHES REQUIRED ----------------------------
    #


    #
    # Check to see how much products that this is an ingredient for need
    #
    my $ingredsOf = $self->get_ingredient_of( [] );
    for my $prod (@$ingredsOf) {
        # see how many batches of it are needed
        for my $ofIng (grep { $_->get_product == $self } @{$prod->get_ingredients([])}) {
            $units_needed_in_month += $prod->get_required_monthly_batches * $prod->get_batch_size_used * $ofIng->get_units_per_unit;
        }
    }

    my $units_needed_in_hour = $units_needed_in_month / $work_hours_in_month;
    my $prod_hours_needed    = $units_needed_in_hour  / $run_time;
    my $batches_needed       = $prod_hours_needed     / $run_time;
    $batches_needed = sprintf( "%.1f", int($batches_needed) ) eq sprintf( "%.1f", $batches_needed ) ? $batches_needed : 1 + int($batches_needed);

    $self->set_required_monthly_batches( $batches_needed ); #*************
    
    #
    #       ----------------------- COSTS ---------------------------
    #
    # Calculate the costs where total = labor + food + packaging + overhead
    #

    my $packaging_cost_per_batch = $self->get_packaging_cost_per_item * $batch_size;
    my $overhead_cost_per_batch  = 0;
    my $labor_cost_per_batch     = 0;
    my $food_cost_per_batch      = $self->get_food_cost_per_batch + $self->get_packaging_cost_per_item * $batch_size;

    # cost of the steps
    for my $step (@$steps) {
        $step->set_is_bottleneck(0);
        my $run_time = $step->run_time( $batch_size );

        for my $emp (@{$step->get_employees([])}) {
            $labor_cost_per_batch += $emp->get_hourly_pay * $run_time;
        }

        $overhead_cost_per_batch += $step->get_overhead_cost_per_run + $step->get_overhead_cost_per_hour * $run_time;
    }
    $self->set_partial_packaging_cost_per_batch( $packaging_cost_per_batch );  #***************
    $self->set_partial_food_cost_per_batch( $food_cost_per_batch );            #***************
    $self->set_partial_labor_cost_per_batch( $labor_cost_per_batch );          #***************
    $self->set_partial_cost_per_batch( $packaging_cost_per_batch + $food_cost_per_batch + $labor_cost_per_batch );          #***************

    for my $ing (@{$self->get_ingredients([])}) {
        my $ingProd = $ing->get_product;
        my $ingredient_count   = $batch_size * $ing->get_units_per_unit;
        my $ingSize = $ingProd->get_batch_size_used;
        if( $ingSize ) {
            my $ingredient_batches = $ingredient_count / $ingSize;
            $food_cost_per_batch += $ingredient_batches * $ingProd->get_food_cost_per_batch;
            $labor_cost_per_batch += $ingredient_batches * $ingProd->get_labor_cost_per_batch;
            $overhead_cost_per_batch += $ingredient_batches * $ingProd->get_overhead_cost_per_batch;
        }
        $packaging_cost_per_batch += $ingredient_count * $ingProd->get_packaging_cost_per_item;
    }

    $self->set_labor_cost_per_batch( $labor_cost_per_batch );         #*************
    $self->set_overhead_cost_per_batch( $overhead_cost_per_batch );   #*************
    $self->set_packaging_cost_per_batch( $packaging_cost_per_batch ); #*************
    $self->set_food_cost_per_batch( $food_cost_per_batch );           #*************

    my $total_cost_per_batch = $labor_cost_per_batch + 
        $food_cost_per_batch + 
        $overhead_cost_per_batch + 
        $packaging_cost_per_batch;
    $self->set_total_cost_per_batch( $total_cost_per_batch );               #*************
    $self->set_total_cost_per_item( $total_cost_per_batch / $batch_size );  #*************
    
    #
    #       ----------------------- PROFIT ---------------------------
    #
    
    my $batch_revenue = $batch_size    * $self->get_sale_price;
    my $batch_profit  = $batch_revenue - $total_cost_per_batch;
    
    if( $batch_revenue ) {
        $self->set_batch_revenue( $batch_revenue );                                            #*************
        $self->set_batch_profit( $batch_profit );                                              #*************
        $self->set_labor_cost_percentage( 100*$labor_cost_per_batch/$batch_revenue );          #*************
        $self->set_packaging_cost_percentage( 100*$packaging_cost_per_batch/$batch_revenue );  #*************
        $self->set_food_cost_percentage( 100*$food_cost_per_batch/$batch_revenue );            #*************
        $self->set_overhead_cost_percentage( 100*$overhead_cost_per_batch/$batch_revenue );    #*************
    } else {
        $self->set_labor_cost_percentage( undef );
        $self->set_packaging_cost_percentage( undef );
        $self->set_food_cost_percentage( undef );
        $self->set_overhead_cost_percentage( undef );
    }

} #calculate


1;

__END__
