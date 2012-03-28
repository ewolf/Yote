package Yote::Sample::SecretCollect;

use base 'Yote::AppRoot';

use Crypt::Passwd;

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
sub init {

    my $self = shift;

    $self->set_riddles( [] );
    $self->set_riddle_count( 0 );

} #init

sub add_riddle {

#    my( $self, $data, $acct_root, $acct ) = @_;

    my( $self,      # This singleton AppRoot object. 
                    # It lives in /apps/Yote::Sample::SecretCollect
                    # Calling 
                    # "var app = $.yote.get_app('Yote::Sample::SecretCollect');"
                    #   on the client side will return only this instance.
        
        $data,      # The data structure sent by the client.
                    # This app is expecting app.add_riddle({question:"ques",answer:"ans"});
        $acct_root, # This is a container specific to the account calling add_riddle
                    # and the SecretCollect app. This is meant to store state data
                    # for the player that does not clash with state data they have
                    # for any other app.
        
        $acct       # The account object the user is logged in as. 
                    # It is created by calling 
                    #   $.yote.create_account( {} );
        ) = @_;

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
    print STDERR Data::Dumper->Dump( [$data->{answer},$data->{question},"SSSSSSSSSS"] );
    $riddle->set_secret_answer( unix_std_crypt( $data->{answer}, 
                                                $data->{question} ) );
    $riddle->set_owner( $acct_root );
    $acct_root->add_to_my_riddles( $riddle );

    #
    # add the riddle to all riddles the app has
    #
    $self->add_to_riddles( $riddle );
    $self->set_riddle_count( 1 + $self->get_riddle_count() );

    return 'riddle added';

} #add_riddle

sub can_start {

    my( $self, $data, $acct_root, $acct ) = @_;

    # need 3 riddles to start guessing
    return @{ $self->get_riddles( [] ) } > 2;
}


sub random_riddle {

    my( $self, $data, $acct_root, $acct ) = @_;

    unless( $self->can_start( $data, $acct_root, $acct ) ) {
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
    my $riddle = $self->_xpath( "/riddles/$riddle_idx" );
    print STDERR Data::Dumper->Dump( [$riddle_idx,$self->get_riddles([]),$riddle] );
    return $riddle; # should standardize the sending of this. have a send success, send error

} #random_riddle

sub my_guess_count {

    my( $self, $data, $acct_root, $acct ) = @_;

    print STDERR Data::Dumper->Dump( ["GUess count",$acct_root] );
    return $acct_root->get_guesses() || 0;

} #my_guess_count

sub my_riddles {

    my( $self, $data, $acct_root, $acct ) = @_;
    return $acct_root->get_my_riddles([]);
} #my_riddles

sub guess_riddle {

    my( $self, $data, $acct_root, $acct ) = @_;

    my $riddle = $data->{riddle};
    my $answer = $data->{answer};

    my $riddle_owner = $riddle->get_owner();

    $riddle->set_guesses( 1 + $riddle->get_guesses() );
    $acct_root->set_guesses( 1 + $acct_root->get_guesses() );

    if( $riddle->get_secret_answer() eq unix_std_crypt( $answer, $riddle->get_question() ) ) {
        #
        # A secret collect! Change ownership and update the stats.
        #
        if( ! $riddle_owner->is( $acct_root ) ) {
            $acct_root->set_collected_count( 1 + $acct_root->get_collected_count() );
            $riddle->set_collect_count( 1 + $riddle->get_collect_count() );

            $riddle_owner->remove_from_my_riddles( $riddle );
            $acct_root->add_to_my_riddles( $riddle );
            $riddle->set_owner( $acct_root );
        }
        return 1;
    } 
    else {
        return 0;
    }
} #guess_riddle


1;

__END__
