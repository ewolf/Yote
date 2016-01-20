package Samp::Step;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Samp::Component';


sub allowedupdates {
    qw(
        name description units_produced hours min_run_time
        employees_required equipment_required
      );
}

sub calculate {
    my $self = shift;
    my $hours = $self->get_hours();
    if( $hours > 0 ) {
        $self->set_production_rate( sprintf( "%.0f", $self->get_units_produced() / $self->get_hours() ) );
    } else {
        $self->set_production_rate( 'n/a' );
    }
    $self->get_product_line()->calculate();
}

1;
