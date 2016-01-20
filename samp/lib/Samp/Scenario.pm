package Samp::Scenario;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Samp::Component';
use Samp::ProductLine;

my $avg_days_in_month = int(365.0 * (5.0 / 7.0) / 12 ); #round downd sweet home 3d

sub allowedUpdates {
    [qw( name 
         description 
         employee_count
         employee_pay_rate
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
}

1;

__END__
