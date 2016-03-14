package Samp::ProductLine;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

use Samp::ProductionStep;
use Samp::RawMaterial;
use Samp::Assign;

sub _allowedUpdates {
    qw( name 
        notes

        is_for_sale

        sale_price
        expected_sales
        expected_sales_per

        batch_size
        batch_unit
        batches_per_month
       );
}

sub _lists {
    { steps                => 'Samp::ProductionStep',
      available_components => 'Yote::Obj',
      raw_materials        => 'Samp::RawMaterial', 
    };
}

sub _gather { 
    shift->get_sales_units;
#    my $self = shift;
#    my $av = $self->get_available_components;
#    return $self->get_sales_units, $av, map { $_, $_->get_item } @$av;
}

sub _init {
    my $self = shift;
    $self->SUPER::_init;
    $self->absorb( {
        sales_units => [qw( day week month year )],

        
        # manually set
        is_for_sale        => 1,
        sale_price         => 0,
        expected_sales     => 0,
        expected_sales_per => 'day',
        
        batch_size         => 0,
        batch_unit         => 'item',
        batches_per_month  => 0,
        
        # calculated
        hours_per_batch          => 0,
        manhours_per_batch       => 0,
        cost_per_batch           => 0, 
        cost_per_month           => 0, 
        cost_per_prod_unit       => 0, 
        available_components     => [],
        revenue_month            => 0,
        batches_needed_per_month => 0,
        yield                    => 0,

        messages => '',
        valid    => 0,
                   } );

} #_init

sub calculate {
    # calculate redux
    my( $self, $msg, $obj ) = @_;

    my $scenario = $self->get_parent;

    my $batch_size = $self->get_batch_size;

    my $valid = 1;
    
    #
    # given
    #   steps
    #   batch size
    #   components
    #
    # calculate 
    #     avail components
    #     component costs/unit
    #
    #     units needed to meet sales expectations
    #     revenue/month
    
    #     batch_time
    #     bottleneck step
    #     manhours for batch
    #     yield

    #
    # avail components, component costs
    #
    my( %seen, %comp2useage );

    my $avail = $self->get_available_components;
    for my $comp (@$avail) {
       $comp2useage{$comp->get_item} = $comp;
    }
    
    my $cost_per_batch = 0;
    for my $comp ( @{$scenario->get_raw_materials}, 
                   grep { $_ != $self }  
                   @{$scenario->get_product_lines} ) {
        $seen{$comp} = 1; #  component, isUsed, amount needed per batch
        my $c2u = $comp2useage{$comp};
        unless( $c2u ) { 
            $c2u = $self->{STORE}->newobj( { item => $comp, attached_to => $self }, 'Samp::Assign' );
            $comp->add_to_assignments( $c2u );
            $comp2useage{$comp} = $c2u;
            push @$avail, $c2u; #<--- add the comp to the material
        }
        if( $c2u->get_use_quantity ) {
            my $comp_costs = $comp->get_cost_per_prod_unit;
            my $quan       = $c2u->get_use_quantity; # units per batch
            $cost_per_batch += $quan * $comp_costs;            
        }
    }
    $self->set_cost_per_batch( $cost_per_batch );
    $self->set_cost_per_month( $cost_per_batch * $self->get_batches_per_month );
    $self->set_cost_per_prod_unit( $batch_size ? $cost_per_batch / $batch_size : undef );
    for my $delme ( grep { ! $seen{$_} } keys %comp2useage ) {
        delete $comp2useage{$delme};
        $self->remove_from_available_components( $delme ); #<--- remove the comp from the material
    }
    
    my $work_hours_in_month = 173; #rounded down
    my $work_days_in_month  = 21; #rounded down

    #
    # units needed by sales expectations
    # expected revenue
    #
    my %times = (  #normalize to month
                   day => 21,
                   week => 52.0/12,
                   month => 1,
                   year  => 1.0/12,
        );
    my $units_needed_in_month = $self->get_expected_sales * $times{ $self->get_expected_sales_per };
    $self->set_revenue_month( $units_needed_in_month * $self->get_sale_price );

    #
    #
    #
    $self->set_batches_needed_per_month( $batch_size ? $units_needed_in_month / $batch_size : undef );

    my $steps = $self->get_steps([]);

    my( $slowest_rate, $bottleneck, $scaled_run_time );
    my $failure_rate = 0;
    my $batch_time = 0;
    my $manhours = 0;
    my $yield = $batch_size;
    for my $step (@$steps) {
        $step->set_is_bottleneck(0);
        $yield -= $yield * $step->get_failure_rate / 100;
        if( $yield < 0 ) {
            $self->set_valid( 0 );
            $self->set_yield( 0 );
            last;
        }
        my $step_rate = $step->get_production_rate;
        my $step_time = $step->run_time( $batch_size );
        $manhours += $step_time * $step->get_number_employees_required;
        $batch_time += $step_time;
        $slowest_rate //= $step_rate;
        $slowest_rate //= $step_rate;
        $bottleneck   //= $step;
        if( $step_rate < $slowest_rate ) {
            $slowest_rate =  $step_rate;
            $bottleneck = $step;
        }
    }
    $bottleneck->set_is_bottleneck(1) if $bottleneck;
    $self->set_hours_per_batch( $batch_time );

    $self->set_items_per_hour( $batch_time ? $yield / $batch_time : undef );
    
    $self->set_manhours_per_batch( $manhours );

    $self->set_manhours_per_month( $manhours * $self->get_batches_per_month );
    
    $self->set_yield( $yield );

    $scenario->calculate;
    
} #calculate


1;

__END__

Given
   batch units
   batch size
   batches per month
   steps

Calculate :
   man hours per batch
   production rate
   cost per batch
   cost per unit
   cost per month
   production step bottleneck
