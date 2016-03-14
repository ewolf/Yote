package Samp::Scenario;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';
use Samp::ProductLine;
use Samp::PeriodicExpense;
use Samp::Employee;
use Samp::Equipment;
use Samp::RawMaterial;

my $avg_days_in_month = int(365.0 * (5.0 / 7.0) / 12 ); #round down

my %times = (  #normalize to month
               day => 21,
               week => 52.0/12,
               month => 1,
               year  => 1.0/12,
    );


sub _allowedUpdates {
    qw( name 
         notes
         description 
         current_product_line
    )
}
sub _lists {
    {
        product_lines => 'Samp::ProductLine',
        employees     => 'Samp::Employee',
        raw_materials => 'Samp::RawMaterial',
        equipment     => 'Samp::Equipment',
        expenses      => 'Samp::PeriodicExpense'
    };
}

sub _init {
    my $self = shift;
    $self->SUPER::_init();
    my $store = $self->{STORE};

    $self->add_entry( 'raw_materials',
                      $store->newobj( {
                          name => 'chocolate',
                          pur_quan  => 5,
                          pur_time  => 'month',
                          pur_price => 70,
                          pur_unit  => '25 pound bag',
                          prod_unit => 'pound',
                          prod_units_per_pur_unit => 25,
                                      }, 'Samp::RawMaterial' ) );
    $self->add_entry( 'employees',
                      $store->newobj( {
                          name       => 'Person A',
                          hourly_pay => 15,
                          hours_per_week => 40,
                                      }, 'Samp::Employee' ) );
    $self->add_entry( 'equipment',
                      $store->newobj( {
                          name => 'mixer',
                                      }, 'Samp::Equipment' ) );

    $self->add_entry( 'expenses',
                      $store->newobj( {
                          name => 'rent',
                          cost => 4500,
                          cost_period => 'month'
                                      }, 'Samp::PeriodicExpense' ) );
    $self->add_entry( 'product_lines',
                      $store->newobj( {
                          name => 'first product',
                                      }, 'Samp::ProductLine' ) );

    $self->calculate;
} #_init

sub calculate {
    my( $self, $type, $listName, $obj, $idx ) = @_;

    if( $type eq 'new_entry' && $listName eq 'product_lines' ) {
        $self->set_current_product_line( $obj );
    } elsif( $type eq 'removed_entry' && $listName eq 'product_lines' ) {
        my $pl = $self->get_product_lines;
        if( @$pl ) {
            $self->set_current_product_line( $idx > $#$pl ? $pl->[$#$pl] : $pl->[$idx] );
        } else {
            $self->set_current_product_line( undef );
        }
    }

    my $hours_in_month = (365.0/12) * 8;
    
    #
    # payroll, manhours
    #
    my $payroll = 0;
    my $hours   = 0;
    for my $emp (@{$self->get_employees([])}) {
        $payroll += $emp->get_monthly_pay;
        $hours   += $emp->get_manhours_month;
    }
    $self->set_monthly_payroll( $payroll );
    $self->set_monthly_assigned_manhours( $hours );

    #
    # periodic expenses
    #
    my $periodic = 0;
    for my $exp (@{$self->get_expenses([])}) {
        $periodic += $exp->get_monthly_expense;
    }
    $self->set_monthly_expenses( $periodic );


    #
    # raw material costs
    #
    my $matcost = 0;
    for my $rm (@{$self->get_raw_materials([])}) {
        $matcost += $rm->get_cost_per_month;
    }
    $self->set_monthly_raw_materials_cost( $matcost );

    # TODO - tally up raw materials used by production to see
    #        if enough is bought

    #
    # production expenses and revenue
    #
    my $prod_costs = 0;
    my $prod_revenue = 0;
    my $manhours_required = 0;

    for my $prod (@{$self->get_product_lines([])}) {

        if( ($type eq 'new_entry' || $type eq 'removed_entry') && ( $listName eq 'raw_materials' || $listName eq 'product_lines' ) ) {
            $prod->calculate( $type, $listName, $obj );
        }

        $prod_costs   += $prod->get_cost_per_month;
        $prod_revenue += $prod->get_revenue_month;
        $manhours_required += $prod->get_manhours_per_month;
    }

    $self->set_monthly_product_costs( $prod_costs );
    $self->set_monthly_product_revenue( $prod_revenue );
    $self->set_monthly_manhours_required( $manhours_required );

    $self->set_total_monthly_costs( $payroll + $periodic + $matcost );

    $self->set_monthly_profit( $prod_revenue - $self->get_monthly_expense );
    
} #calculate

1;

__END__

Given
   Employees
   Expenses
   RawMaterials
   ProductLines

Calculate :
   Payroll
   Monthly Expenses
   Raw Material costs
   Total Monthly Costs
   Manhours Required
   Expected Revenue
   Profit
   Per sales item : cost breakdown, profit
