package Test;

use strict;
use warnings;

use Yote::Server;

use base 'Yote::Server::App';

sub test {
    my( $self, @args ) = @_;
    return ( "FOOBIE", "BLECH", @args );
}

1;
