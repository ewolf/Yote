package Yote::SE::Player;

use strict;

use Yote::Obj;

use base 'Yote::Obj';

sub message {
    my( $self, $msg ) = @_;
    my $game = $self->get_game();
    my $msgs = $self->get_messages([]);   
    push( @{$msgs->[$game->get_turn()]}, $msg );
}

sub last_messages {
    my $self = shift;
    my $game = $self->get_game();
    return [] if $game->get_turn() == 0;
    my $msgs = $self->get_messages([]);
    $msgs->[$game->get_turn()-1] ||= [];
    return $msgs->[$game->get_turn()-1];
}

sub add_order {
    my( $self, $ord ) = @_;
    my $game = $self->get_game();
    my $ords = $self->get_orders([]);
    push( @{$ords->[$game->get_turn()]}, $ord );
}

sub orders {
    my $self = shift;
    my $game = $self->get_game();
    my $ords = $self->get_orders([]);
    $ords->[$game->get_turn()] ||= [];
    return $ords->[$game->get_turn()];
}

sub clear_orders {
    my $self = shift;
    my $game = $self->get_game();
    my $ords = $self->get_orders([]);
    $ords->[$game->get_turn()] = [];
}

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut
