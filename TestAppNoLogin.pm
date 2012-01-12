package GServ::TestAppNoLogin;

#
# created for the html unit tests
#

use strict;

use GServ::Obj;

use base 'GServ::AppRoot';

use vars qw($VERSION);

$VERSION = '0.01';

#
# need subs to return : scalars, lists, hashes, g-objects
#

sub get_scalar {
    my( $self, $data, $acct ) = @_;
    return "BEEP";
}


1;

__END__
