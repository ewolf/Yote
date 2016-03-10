use strict;
use warnings;

use Yote;

use Samp::Scenario;

use Data::Dumper;
use File::Temp qw/ :mktemp tempdir /;
use Test::More;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    use_ok( "Yote" ) || BAIL_OUT( "Unable to load 'Yote'" );
    use_ok( "Samp::Scenario" ) || BAIL_OUT( "Unable to load 'Samp::Scenario'" );
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

my $dir = tempdir( CLEANUP => 1 );
test_suite();
done_testing;

exit( 0 );


sub test_suite {

    my $store = Yote::open_store( $dir );
    my $yote_db = $store->{_DATASTORE};
    my $root_node = $store->fetch_root;

    my $scene = $store->newobj( { name => "Test Scenario" }, 'Samp::Scenario' );

    my( $exp ) = $scene->add_entry( 'expenses' );
    $exp->update( {
        name => 'rent',
        cost => 4000,
        cost_period => 'month',
                  } );
    is( $scene->get_total_monthly_costs, 4000, 'first expense - total cost' );
    is( $scene->get_monthly_expenses, 4000, 'first expense - monthly expenses' );
    is( $scene->get_monthly_payroll, 0, 'first expense - no payroll yet' );

    ( $exp ) = $scene->add_entry( 'expenses' );
    $exp->update( {
        name => 'utils',
        cost => 600,
        cost_period => 'month',
                  } );
    is( $scene->get_total_monthly_costs, 4600, 'next expense - total costs' );
    is( $scene->get_monthly_expenses, 4600, 'next expense - monthly expenses' );
    is( $scene->get_monthly_payroll, 0, 'next expense - no payroll yet' );
    is( $scene->get_monthly_raw_materials_cost, 0, 'next expense - no raw mats' );
    
    my( $raw ) = $scene->add_entry( 'raw_materials' );
    $raw->update( {
        pur_quan                => 4,
        pur_price               => 88,
        pur_unit                => 'flat of raspberries',
        prod_unit               => 'oz',
        prod_units_per_pur_unit => 100
                  } );

    is( $scene->get_total_monthly_costs, 4952, 'first raw - total costs' );
    is( $scene->get_monthly_expenses, 4600, 'first raw - monthly expenses' );
    is( $scene->get_monthly_payroll, 0, 'first raw - no payroll yet' );
    is( $scene->get_monthly_raw_materials_cost, 352, 'first raw - monthly cost' );

    ( $raw ) = $scene->add_entry( 'raw_materials' );
    $raw->update( {
        pur_quan                => 1,
        pur_price               => 100,
        pur_unit                => '50 pound bag of chocolate',
        prod_unit               => 'pound',
        prod_units_per_pur_unit => 50,
                  } );
    is( $scene->get_total_monthly_costs, 5052, 'second raw - total costs' );
    is( $scene->get_monthly_expenses, 4600, 'second raw - monthly expenses' );
    is( $scene->get_monthly_payroll, 0, 'second raw - no payroll yet' );
    is( $scene->get_monthly_raw_materials_cost, 452, 'second raw - monthly cost' );

    my( $emp ) = $scene->add_entry( 'employees' );
    $emp->update( {
        name => "person1", #2600, 7652
        hourly_pay => 15,
        hours_per_week => 40
                  } );
    is( $scene->get_total_monthly_costs, 7652, 'first employee - total costs' );
    is( $scene->get_monthly_expenses, 4600, 'first employee - monthly expenses' );
    is( $scene->get_monthly_payroll, 2600, 'first employee - no payroll yet' );
    is( $scene->get_monthly_raw_materials_cost, 452, 'first employee - raw costs' );

    my( $line ) = $scene->add_entry( 'product_lines' );
    $line->update( {
        name => 'caramels',
        is_for_sale => 1,
        sale_price => 2,
        expected_sales => 40,
        expected_sales_per => 'day',
        batch_size => 100,
        batch_unit => 'item',
        batches_per_month => 4,
                   } );
    is( scalar(keys %{$line->get_comp2useage}), 2, "components to usage has values" );
    is( $scene->get_total_monthly_costs, 7652, 'first line - total costs' );
    is( $scene->get_monthly_expenses, 4600, 'first line - monthly expenses' );
    is( $scene->get_monthly_payroll, 2600, 'first line - no payroll yet' );
    is( $scene->get_monthly_raw_materials_cost, 452, 'first line - raw costs' );
    is( int($scene->get_monthly_product_revenue), 1680, 'first line - revenue' );

    is( $line->get_manhours_per_batch, 0, "line - no manhours yet" );
    is( $line->get_hours_per_batch, 0, "line - no hours yet" );
    is( $line->get_cost_per_batch, 0, "line - no cost per batch yet" );
    is( $line->get_cost_per_prod_unit, 0, "line - no cost per unit yet" );
    is( $line->get_cost_per_month, 0, "line - no cost per month yet" );

    # add a step for time
    my( $step ) = $line->add_entry( 'steps' );
    $step->update( {
        number_employees_required    => 3,
        number_produced_in_timeslice => 42,
        timeslice_mins               => 18,
                   } );
    # per hour production 42/(60*18)
    is( $scene->get_total_monthly_costs, 7652, 'first step - total costs' );
    is( $scene->get_monthly_expenses, 4600, 'first step - monthly expenses' );
    is( $scene->get_monthly_payroll, 2600, 'first step - no payroll yet' );
    is( $scene->get_monthly_raw_materials_cost, 452, 'first step - raw costs' );
    is( int($scene->get_monthly_product_revenue), 1680, 'first step - revenue' );

    is( sprintf( "%.2f", $line->get_manhours_per_batch ), 2.14, "step - now with manhours" );
    is( sprintf( "%.2f", $line->get_hours_per_batch ), 0.71, "step - no hours yet" );
    is( $line->get_cost_per_batch, 0, "step - no cost per batch yet" );
    is( $line->get_cost_per_prod_unit, 0, "step - no cost per unit yet" );
    is( $line->get_cost_per_month, 0, "step - no cost per month yet" );

    # add some raw materials for cost
    ( $raw ) = $scene->add_entry( 'raw_materials' );
    $raw->update( {
        pur_quan                => 3,
        pur_price               => 25,
        pur_unit                => 'bucket o frosting',
        prod_unit               => 'gallon',
        prod_units_per_pur_unit => 5
                  } );

    $line->add_entry( 'raw_materials', $raw );

    my $frost_use = $line->get_comp2useage->{$raw};
    $frost_use->update( {
        is_used => 1,
        use_quantity => 4,
                        } );
    # 5*4  <---20<--- cost of frosting per batch
    #                x 4 batches --> 80 /month

    is( scalar(keys %{$line->get_comp2useage}), 3, "components to usage has values" );
    is( $scene->get_total_monthly_costs, 7727, 'first step - total costs' );
    is( $scene->get_monthly_expenses, 4600, 'first step - monthly expenses' );
    is( $scene->get_monthly_payroll, 2600, 'first step - no payroll yet' );
    is( $scene->get_monthly_raw_materials_cost, 527, 'first step - raw costs' );
    is( int($scene->get_monthly_product_revenue), 1680, 'first step - revenue' );

    is( sprintf( "%.2f", $line->get_manhours_per_batch ), 2.14, "step - now with manhours" );
    is( sprintf( "%.2f", $line->get_hours_per_batch ), 0.71, "step - no hours yet" );
    is( $line->get_cost_per_batch, 20, "step - no cost per batch yet" );
    is( $line->get_cost_per_prod_unit, .20, "step - no cost per unit yet" );
    is( $line->get_cost_per_month, 80, "step - no cost per month yet" );

}

__END__
