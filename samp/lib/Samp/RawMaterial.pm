package Samp::RawMaterial;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

use Samp::Step;
use Samp::Ingredient;

sub _allowedUpdates {
    qw( name 
          notes
          
          pur_quan
          pur_time
          pur_price
          pur_unit
          prod_units_per_pur_unit
          prod_unit

       )
}

#
# example, buying 3 -  50# bags of chocolate per month at 60$/bag
#     provides 150 pounds of chocolate per month at a cost of
#       6/5 $ per #
#      
#   pur_quan - 3
#   pur_unit - '50# bag'
#   prod_units_per_purchase_unit - 50
#   prod_unit - '#'
#   pur_price - 60 $
#   prod_unit_cost - 6/5$
#   prod_units_month - 150
#


sub _init {
    my $self = shift;
    $self->SUPER::_init;
    $self->set_name( 'flour' );
    $self->set_pur_quan( 0 );
    $self->set_pur_time( 'month' );
    $self->set_pur_price( 0 );
    $self->set_pur_unit( '50 pound bag' );
    $self->set_prod_unit( 'pound' );
    $self->set_prod_units_per_pur_unit( 50 );
    $self->set_cost_period_types( [qw( month quarter year )] );
    
    $self->set_cost_per_month( 0 );        #calculated
    $self->set_cost_per_prod_unit( 0 );    #calculated
} #_init

sub _gather { 
    shift->get_cost_period_types;
}

my %times = (  #normalize to month
               day => 21,
               week => 52.0/12,
               month => 1,
               year  => 1.0/12,
    );


sub calculate {
    # calculate redux
    my $self = shift;

    my $price = $self->get_pur_price;
    my $quan  = $self->get_pur_quan;
    $self->set_cost_per_month( $quan * $price * $times{$self->get_pur_time} );
    my $prod_per_pur = $self->get_prod_units_per_pur_unit;
    my $prod_units = $prod_per_pur * $quan;

    $self->set_cost_per_prod_unit( $price ? $price / $prod_per_pur : undef );
    my $scene = $self->get_parent;

    my $lines = $scene->get_product_lines;

    # calculate useage in product lines
    my $usage = 0;
    for my $line (@$lines) {
        my $comps = $line->get_available_components;
        for my $comp (grep { $_->get_item == $self } @$comps) {
            $usage += $comp->get_use_quantity;
        }
    }
    $self->set_units_used( $usage );
    
    map { $_->calculate( "RawMaterial", $self ) } @$lines;

    $scene->calculate( 'RawMaterial', $self );
    
} #calculate


1;

__END__
