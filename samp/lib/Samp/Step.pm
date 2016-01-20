package Samp::Step;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;
use base 'Yote::ServerObj';

sub _init {
    my $self = shift;
    $self->set_unit_per_hour( 0 );
    $self->set_overhead_time( 0 );
    $self->set_min_time( 0 );
}



1;
