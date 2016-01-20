package Samp::Scenario;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';
use Samp::ProductLine;
use Samp::PeriodicExpense;
use Samp::Employee;
use Samp::Equipment;

my $avg_days_in_month = int(365.0 * (5.0 / 7.0) / 12 ); #round down

sub _allowedUpdates {
    [qw( name 
         notes
         description 
         current_product_lines
    )]
}
sub _lists {
    {
        product_lines => 'Samp::ProductLine',
        employees     => 'Samp::Employee',
        equipment     => 'Samp::Equipment',
        expenses      => 'Samp::PeriodicExpense'
    };
}

sub _init {
    my $self = shift;
    $self->SUPER::_init();
    $self->add_entry( {listName => 'product_lines',
                       itemArgs => {
                           name => 'first product',
                       } } );
    $self->add_entry( {listName => 'employees',
                       itemArgs => {
                           name       => 'PersonA',
                           hourly_pay => 15,
                           hours_per_week => 40,
                       } } );
    $self->add_entry( {listName => 'equipment',
                       itemArgs => {
                           name => 'mixer',
                       } } );
    $self->add_entry( {listName => 'expenses',
                       itemArgs => {
                           name => 'rent',
                           cost => 4500,
                           cost_period => 'month'
                       } } );

    $self->calculate;
} #_init

sub _on_add {
    my( $self, $listName, $obj ) = @_;
    if( $listName eq 'product_lines' ) {
        $self->set_current_product_lines( $obj );
    }
}


sub calculate {
    my $self = shift;
    my $hours_in_month = (365.0/12) * 8;

    #
    # payroll,
    #
    my $payroll = 0;
    for my $emp (@{$self->get_employees([])}) {
        $payroll += $emp->get_hourly_pay * $emp->get_hours_per_week * 52 / 12;
    }
    $self->set_monthly_payroll( $payroll );

    #
    # periodic expenses
    #
    my $periodic = 0;
    my( %factor ) = ( day => 1/21, month => 1, week => 12.0/52, quarter => 3, year => 12,  );
    for my $exp (@{$self->get_expenses([])}) {
        my $fact = $factor{$exp->get_cost_period};
        $periodic += $exp->get_cost / $fact if $fact;
    }
    $self->set_monthly_overhead( $periodic );

    #
    # production expenses and revenue
    #
    my $prod_costs = 0;
    my $prod_revenue = 0;
    for my $prod (@{$self->get_product_lines([])}) {
        $prod_costs += $prod->get_partial_cost_per_batch * $prod->get_required_monthly_batches;
        my $fact = $factor{$prod->get_expected_sales_per};
        $prod_revenue += $prod->get_sale_price * $prod->get_expected_sales / $fact if $fact;
    }
    $self->set_monthly_product_costs( $prod_costs );
    $self->set_montly_product_revenue( $prod_revenue );

    $self->set_monthly_expense( $prod_costs + $payroll + $periodic );

    $self->set_monthly_profit( $prod_revenue - $self->get_monthly_expense );
    
} #calculate

1;

__END__

Calculate :
   Itemized periodic expenses, payroll
