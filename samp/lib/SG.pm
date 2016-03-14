package SG;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;

use base 'Yote::Server::App';

sub _init {
    my $self = shift;
    $self->SUPER::_init();
    $self->add_entry( 'games' );
}

sub _allowedUpdates {
    'current_scenario';
}
sub _lists {
    {
        games => 'SG::Game',
    };
}

sub calculate {
    my( $self, $type, $listName, $scen, $idx ) = @_;

}

# handy RESET for testing
sub reset {
    my $self = shift;
    $self->set_games( [] );
}

1;

__END__
