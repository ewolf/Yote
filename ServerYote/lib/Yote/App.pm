package Yote::App;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;

use base 'Yote::ServerApp';

sub login {
    my( $self, $un, $pw ) = @_;
#    return "Tried to log in with '$un' and '$pw'";
    return $self->{STORE}->newobj( {
        user => $un,
        pwww => $pw,                                   } );

} #login

1;

__END__
