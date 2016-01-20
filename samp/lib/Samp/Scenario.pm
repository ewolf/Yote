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
    $self->set_overhead(0);
} #_init

sub calculate {
    my $self = shift;
    my $hours_in_month = (365.0/12) * 8;
    $self->set_employee_monthly_cost( $self->get_employee_count() * $self->get_employee_pay_rate() * $hours_in_month );
}

1;

__END__
