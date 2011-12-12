package GServ::SE::SEApp;

use strict;

use GServ::AppObj;

use base GServ::AppObj;

sub create_game {
    my( $self, $data, $acct ) = @_;

    my $games = $self->get_games({});
    my $game = new GServ::SE::StellarExpanse();
    my $id = GServ::ObjProvider::get_id( $game );
    $games->{$id} = $game;

    my $acct_root = $self->get_account_root();

} #create_game




1;

__END__


qq~
Here is where we define the interface that the StellarExpanse UI uses


* submit_orders( game, turn, orders, acct )
* get_orders( game, turn, acct )
* mark_as_ready( game, turn, acct )
* create_game( data, acct )
* join_game( data, acct )
* get_games( data, acct )

~
