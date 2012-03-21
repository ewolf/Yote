package Yote::Sample::SecretCollect;

use base 'Yote::AppRoot';

use Crypt::Passwd;

sub add_riddle {
    my( $self, $data, $acct_root, $acct ) = @_;
    my $riddle = new Yote::Obj();
    $riddle->set_question( $data->{question} );
    $riddle->set_secret_answer( unix_std_crypt( $data->{answer}, $data->{question} ) );
    $riddle->set_owner( $acct_root );
    $acct_root->add_to_my_riddles( $riddle );

    $self->add_to_riddles( $riddle );
    $self->set_riddle_count( 1 + $self->get_riddle_count() );

    return { msg => 'riddle added' };
} #add_riddle

sub guess_riddle {
    my( $self, $data, $acct_root, $acct ) = @_;
    my $riddle = $data->{riddle};
    my $answer = $data->{answer};

    my $riddle_owner = $riddle->get_owner()

    $riddle->set_guesses( 1 + $riddle->get_guesses() );

    if( $riddle->get_secret_answer() eq unix_std_crypt( $answer, $riddle->get_question() ) ) {
	$acct_root->set_correct_answers( 1 + $acct_root->get_correct_answers() );
	my $guessers = $riddle->get_correct_guessers( {} );

	# count only the first time a user guesses a riddle
	unless( $guessers->{ $acct->get_handle() } ) {
	    $guessers->{ $acct->get_hanle() } = 1;
	    $riddle->set_correct_count( 1 + $riddle->get_correct_count() );

	    $riddle_owner->set_others_guessed_correctly_count( 1 + $riddle_owner->get_others_guessed_correctly_count() );
	    $self->set_correct_guesses( 1 + $self->get_correct_guesses() );
	}
	return { msg => 'You got the right answer' };
		     
    } 
    else {
	my $guessers = $riddle->get_wrong_guessers( {} );
	$guessers->{ $acct->get_handle() }++;
	$riddle->set_incorrect_count( 1 + $riddle->get_incorrect_count() );

	$riddle_owner->set_others_guessed_incorrectly_count( 1 + $riddle_owner->get_others_guessed_incorrectly_count() );
	$self->set_wrong_guesses( 1 + $self->get_wrong_guesses() );
	return { msg => 'You got the wrong answer' };
    }
} #guess_riddle

sub my_stats {
    my( $self, $data, $acct_root, $acct ) = @_;

    my $riddles = $acct_root->get_my_riddles([]);
    

    return { 
	correct_guesses   => 1,
	incorrect_guesses => 1,
	others_correct_guesses   => 1,
	others_incorrect_guesses => 1,
	my_riddles               => $riddles,
    };
    

} #my_stats

sub random_riddle {
    my( $self, $data, $acct_root, $acct ) = @_;
    my $riddle_count = $self->get_riddle_count();
    my $riddle_idx = int( rand( $riddle_count ) );
    my $riddle = Yote::ObjProvider::xpath( "/riddles/$riddle_idx" );
    return { riddle => $riddle };
} #random_riddle


1;

__END__
