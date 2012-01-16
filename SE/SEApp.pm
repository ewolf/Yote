package Yote::SE::SEApp;

use strict;

use Yote::AppRoot;
use Yote::SE::SEGame;
use Yote::SE::StellarExpanse;

use base 'Yote::AppRoot';

sub create_game {
    my( $self, $data, $acct ) = @_;

    my $games = $self->get_games({});
    my $game = new Yote::SE::SEGame();
    $game->set_name( $data->{name} );
    $game->set_number_players( $data->{number_players} );
    $game->set_created_by( $acct );
    my $id = Yote::ObjProvider::get_id( $game );
    $games->{$id} = $game;

    my $acct_root = $self->get_account_root( $acct );
    $acct_root->add_to_my_games( $game );

    return { msg => 'created game' };
} #create_game


sub submit_orders {
    my( $self, $data, $acct ) = @_;
    my $game = fetch( $data->{game} );
    my $player = $game->get_player( $acct );
    if( $player ) {
        if( $data->{turn} == $game->get_turn() ) {
            $player->get_orders([])->[$data->{turn}] = $data->{orders};
            return { msg => "Submitted orders for turn ".$data->{turn} };
        } else {
            return { err => "Turn already over for these orders" };
        }
    }
    return { err => "Not part of this game" };
} #submit_orders

sub get_orders {
    my( $self, $data, $acct ) = @_;
    my $game = fetch( $data->{game} );
    my $player = $game->get_player( $acct );
    if( $player ) {
        my $orders = $player->get_orders([])->[$game->get_turn()];
        return { d => $orders, msg => "got orders for turn ".$game->get_turn() };
    }
    return { err => "Not part of this game" };
} #get_orders

sub mark_as_ready {
    my( $self, $data, $acct ) = @_;
    my $game = fetch( $data->{game} );    
    my $player = $game->get_player( $acct );
    if( $player ) {
        if( $game->get_turn() > $data->{turn} ) {
            return { err => "Turn $data->{turn} already over" };
        }
        $player->get_ready([])->[$game->get_turn()] = $data->{ready};
        if( $game->is_ready() ) {
            $game->take_turn();
        }
        return { msg => "marked as".($data->{ready}?" ready ":" unready ")." for turn ".$game->get_turn() };
    }
    return { err => "Not part of this game" };
    
} #mark_as_ready

sub join_game {
    my( $self, $data, $acct ) = @_;
    my $game = fetch( $data->{game} );
    if( $game ) {
        return $game->register_player( $acct );
    }
    return { err => "game not found" };
} #join_game

sub get_games {
    my( $self, $data, $acct ) = @_;

    my $games = values( %{$self->get_games({})} );
    
    # filter to the games that are wanted
    given( $data->{filter} ) {
	when('mine') {
	    $games = [grep { $acct->is( $_->get_created_by() ) } @$games];
	}
	when( 'joined' ) {
	    $games = [grep { $_->get_player( $acct ) } @$games];
	}
	when( 'active' ) {
	    $games = [grep { $_->get_active() } @$games];
	}
	when( 'pending' ) {
	    $games = [grep { $_->get_active() == 0 } @$games];
	}
    }
    return { r => [map {[$_->{ID},$_->values]} @$games] };
} #get_games

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut

Here is where we define the interface that the StellarExpanse UI uses


* create_game( data, acct )
* submit_orders( game, turn, orders, acct )
* get_orders( game, turn, acct )
* mark_as_ready( game, turn, acct )
* join_game( data, acct )
* get_games( data, acct )
