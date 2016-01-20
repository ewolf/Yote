package Bakery;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;

use base 'Yote::ServerApp';

sub _init {
    my $self = shift;
}

sub calc { 
    my( $self, @data ) = shift;

    # 1 get the incoming 

    $self->set_calcResult( $data[0] + $data[1] );
    $self->set_hourCost( 12 );

    print STDERR Data::Dumper->Dump(["CALC", $self]);
    return $self;
}

1;

__END__
