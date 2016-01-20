package Samp::Scenario;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';
use Samp::ProductLine;

my $avg_days_in_month = int(365.0 * (5.0 / 7.0) / 12 ); #round down

sub _allowedUpdates {
    [qw( name 
         description 
         employee_count
         employee_pay_rate
         monthly_rent
         monthly_utilities
         current_product_lines
    )]
}
sub _lists {
    {
        product_lines => 'Samp::ProductLine',
    };
}

sub _init {
    my $self = shift;
    $self->SUPER::_init();
    $self->set_current_product_lines( $self->add_entry( {listName => 'product_lines' } ) );
    $self->set_employee_count(3);
    $self->set_employee_pay_rate(15);
    $self->set_monthly_rent(0);
    $self->set_monthly_utilities(0);

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
    $self->set_employee_monthly_cost( $self->get_employee_count() * $self->get_employee_pay_rate() * $hours_in_month );
    $self->set_monthly_cost( $self->get_employee_monthly_cost + $self->get_monthly_utilities + $self->get_monthly_rent );
}

1;

__END__
