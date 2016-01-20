package Samp::ProductLine;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Samp::Component';

use Samp::Step;

sub allowedupdates {
    qw( name description units_produced hours food_cost
        sale_price packaging_cost
       );
}

sub lists {
    employees => 'Samp::Employee',
    steps     => 'Samp::Step',
}

#
# avg hours in month? est 52 weeks
# 52*40/12 --> 173 hours/month
#

sub calc {
    my $self = shift;
    my $work_hours_in_month = 173;

    # find monthly costs
    
    
    # loop thru all steps to find the bottleneck
}

sub calculate {
    my $self = shift;

    my $steps = $self->get_steps([]);
    my $rate;
    for my $step (@$steps) {
        my $step_rate = $step->get_production_rate();
        $rate //= $step_rate;
        $rate = $step_rate < $rate ? $step_rate : $rate;
    }

    $self->set_production_rate( $rate );
}

1;

__END__
