package Samp::Scenario;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Samp::Component';
use Samp::ProductLine;

my $avg_days_in_month = int(365.0 * (5.0 / 7.0) / 12 ); #round down

sub allowedUpdates {
    [qw( name 
         description 
         employee_count
         employee_pay_rate
         current_product_line
         monthly_rent
         monthly_utilities
    )]
}
sub lists {
    {
        employees => 'Samp::Employee',
        equipment => 'Samp::Equipment',
        product_lines => 'Samp::ProductLine',
    };
}

sub _init {
    my $self = shift;
    $self->SUPER::_init();
    $self->set_number_of_employees(3);
    $self->set_employee_pay_rate(15);
    $self->set_monthly_rent(0);
    $self->set_monthly_utilities(0);

    $self->calculate;
} #_init

sub calculate {
    my $self = shift;
    my $hours_in_month = (365.0/12) * 8;
    $self->set_employee_monthly_cost( $self->get_employee_count() * $self->get_employee_pay_rate() * $hours_in_month );
    $self->set_monthly_cost( $self->get_employee_monthly_cost + $self->get_monthly_utilities + $self->get_monthly_rent );
}

1;

__END__
