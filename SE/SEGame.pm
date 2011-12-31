package GServ::SE::SEGame;

use GServ::Obj;

use Data::Dumper;

use base 'GServ::Obj';

sub get_player {
    my( $self, $acct_or_id ) = @_;
    if( ref( $acct_or_id ) ) {
	return $self->get_players({})->{$acct_or_id->{ID}};
    }
    return $self->get_players({})->{$acct_or_id};
} #get_player

sub players_needed_to_begin {
    my $self = shift;
    return $self->get_number_players() - scalar(keys %{$self->get_players({})});
} #players_needed_to_begin

sub register_player {
    my( $self, $name, $acct ) = @_;
    return { err => "game is now full" } unless $self->players_needed_to_beging() > 0;
    return { err => "name '$name' already taken" } if grep { lc($name) eq lc($_->get_name()) } values %{$self->get_players({})};
    return { err => "already joined game" } if grep { $acct->{ID} == $_ } keys %{$self->get_players()};
    my $player = new GServ::SE::Player();
    $self->get_players({})->{$acct->{ID}} = $player;
    return { msg => "registered with game ".$self->get_name() };
} #register_players

sub is_ready {
    my $self = shift;
    my $players = $self->get_players({});
    if( scalar( keys %$players ) ) {
	if( grep { $_->get_ready() == 0 } value %$players ) {
	    return 0;
	}
	return 1;
    }
    return 0;
} #is_ready

sub take_turn {
    print STDERR Data::Dumper->Dump(['taking turn']);
} #take_turn

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut
