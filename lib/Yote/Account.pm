package Yote::Account;

use base 'Yote::Messenger';

sub upload_avatar {
    my( $self, $data, $acct ) = @_;
    my $login = $acct->get_login();
    if( $login->get__password() eq $self->_encrypt_pass( $data->{p}, $login ) ) {
	$self->set_avatar( $data->{avatar_file} );
	return "set avatar";
    }
    die "incorrect password";
}

1;

__END__
