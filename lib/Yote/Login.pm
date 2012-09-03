package Yote::Login;

use strict;

use base 'Yote::Obj';

sub init {
    my $self = shift;
    $self->set__allowed_access({});
}

#
# Can either be reset by logged in account, or by a recovery link.
#
sub reset_password {
    my( $self, $args, $account ) = @_;

    my $newpass        = $args->{p};
    my $newpass_verify = $args->{p2};

    die "Passwords don't match" unless $newpass eq $newpass_verify;

    # logged in an resetting
    my $login = $account->get_login();
    $login->set__password( $self->_encrypt_pass($newpass, $login) );
    return "Password Reset";

} #reset_password


1;

__END__
