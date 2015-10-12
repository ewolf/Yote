package Yote::App;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;

use base 'Yote::ServerApp';

sub login {
    my( $self, $un, $pw ) = @_;
    print STDERR Data::Dumper->Dump(["LOGIN CALLED WITH $un,$pw"]);
    return "Tried to log in with '$un' and '$pw'";

} #login

1;

__END__
