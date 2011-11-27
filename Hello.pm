package GServ::Hello;

use GServ::AppObj;

use base GServ::AppObj;


sub hello {
    my( $self, $data, $acct ) = @_;
    my $name = $acct ? $acct->get_handle() : '?';
    return { r => "hello there $name" };
}

1;
