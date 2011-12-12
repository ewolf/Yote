package GServ::Hello;

use strict;

use GServ::AppRoot;

use base GServ::AppRoot;


sub hello {
    my( $self, $data, $acct ) = @_;
    my $name = $acct ? $acct->get_handle() : '?';
    return { r => "hello there $name" };
}

1;
