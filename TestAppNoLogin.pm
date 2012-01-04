package GServ::TestAppNoLogin;

#
# created for the html unit tests
#

use strict;

use GServ::Obj;

use base 'GServ::AppRoot';

#
# need subs to return : scalars, lists, hashes, g-objects
#

sub get_scalar {
    my( $self, $data, $acct ) = @_;
    return "BEEP";
}


1;
