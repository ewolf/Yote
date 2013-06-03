package Yote::Sample::SecretCollect;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';


use base 'Yote::AppRoot';


#
# Init is run only the first time this Yote object is created and assigned
#   an ID by the system.
#
# This will not be run if the object is loaded and instantiated
#    from the Yote data store. 
# You do not need to call any of the setters to allow the use of riddles or
#    set_riddle_count. Calling it here will mean that it starts with an empty
#    riddles list.
#
sub _init {

    my $self = shift;

    $self->set_riddles( [] );
    $self->set_riddle_count( 0 );

} #_init

sub _init_account {
    my( $self, $acct ) = @_;
    $acct->set_guesses( 0 );
    $acct->set_my_riddles( [] );
}

#
# Add a riddle to your collection. May do this until you have 3.
#
sub add_riddle {

    my( $self, $data, $acct ) = @_;

    #
    # Create a new riddle object and add it to the account root's riddle supply.
    # encrypt the riddle to hide its answer.
    #
    # The riddle methods 'set_question', 'set_secret_answer', 'set_owner'
    #    are automatically there and need no definition.
    # The account root
    #
    my $riddle = new Yote::Obj();
    $riddle->set_question( $data->{question} );
    $riddle->set__answer( $data->{answer} );   # _answer won't be sent to the client because it starts with an underscore
    $riddle->set_owner( $acct );
    $acct->add_to_my_riddles( $riddle );

    #
    # add the riddle to all riddles the app has
    #
    $self->add_to_riddles( $riddle );
    $self->set_riddle_count( 1 + $self->get_riddle_count() );

    return 'riddle added';

} #add_riddle

#
# Can start playing if you have 3 or more questions.
#
sub can_start {

    my( $self, $data, $acct ) = @_;

    # need 3 riddles to start guessing
    return @{ $acct->get_my_riddles( ) } > 2;
}

#
# Give a random riddle to the guesser
#
sub random_riddle {

    my( $self, $data, $acct ) = @_;

    unless( $self->can_start( $data, $acct ) ) {
        die "Must have 3 riddles to guess others";
    }

    my $riddle_count = $self->get_riddle_count();

    if( $riddle_count == 0 ) {
        die "there are no riddles to guess";
    }

    #
    # Pick the riddle without having to load in the whole riddle array :
    #
    my $riddle_idx = int( rand( $riddle_count ) );
    my $riddle = $self->_hash_fetch( 'riddles', $riddle_idx );
    return $riddle; # should standardize the sending of this. have a send success, send error

} #random_riddle

sub guess_riddle {

    my( $self, $data, $acct ) = @_;

    my $riddle = $data->{riddle};
    my $answer = $data->{answer};

    my $riddle_owner = $riddle->get_owner();

    $riddle->set_guesses( 1 + $riddle->get_guesses() );
    $acct->set_guesses( 1 + $acct->get_guesses() );

    if( $riddle->get__answer() eq $answer ) {
        #
        # A secret collect! Change ownership and update the stats.
        #
        if( ! $riddle_owner->_is( $acct ) ) {
            $acct->set_collected_count( 1 + $acct->get_collected_count() );
            $riddle->set_collect_count( 1 + $riddle->get_collect_count() );

            $riddle_owner->remove_from_my_riddles( $riddle );
            $acct->add_to_my_riddles( $riddle );
            $riddle->set_owner( $acct );
        }
        return 1;
    } 
    else {
        return 0;
    }
} #guess_riddle


1;

__END__

=head1 PUBLIC METHODS

=over 4

=item guess_riddle

=item add_riddle

=item random_riddle

=item can_start


=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
