package Samp::Scenario;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Samp::Component';
use Samp::ProductLine;

sub allowedUpdates {
    [qw( name description )]
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
    $self->SUPER::_init;
    $self->set_overhead(0);
} #_init

sub calculate {
    my( $self ) = @_;
    my $lines = $self->get_product_lines([]);

    my $rate;
    for my $line (@$lines) {
        my $line_rate = $line->get_production_rate();
        $rate //= $line_rate;
        $rate = $line_rate < $rate ? $line_rate : $rate;
    }
}

1;

__END__
