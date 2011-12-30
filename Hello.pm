package GServ::Hello;

use strict;

use base 'GServ::AppRoot';

sub hello {
    my( $self, $data, $acct ) = @_;
    $self->set_said( 1 + $self->get_said() );
    my $name = $data->{name};
    return { r => "hello there '$name'. I have said hello ".$self->get_said()." times." };
}

1;
