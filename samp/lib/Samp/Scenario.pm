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
    my( $self ) = @_;
    my $lines = $self->get_product_lines([]);

    my( $slowest_rate, $bottleneck );
    for my $line (@$lines) {
        my $line_rate = $line->get_production_rate();
        $rate //= $line_rate;
        if( $line_rate < $slowest_rate ) {
            $slowest_rate =  $line_rate;
            $bottleneck = $line;
        }
        
        # rate is per hour. Calculate how long it would take
        # to do a production run of X
    }

    my $hours = 0;
    for my $line (@$lines) {
        my $line_rate = $line->get_production_rate();
        if( $line_rate > 0 ) {
            $hours += $slowest_rate / $line_rate; # items / (items/hour)  --> hours
        }
    }
    
}

1;

__END__
