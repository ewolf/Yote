package Yote::Login;

use strict;

use base 'Yote::Obj';

#
# Can either be reset by logged in account, or by a recovery link.
#
sub reset_password {
    my( $self, $args, $account ) = @_;

    my $oldpass        = $args->{op};
    my $newpass        = $args->{p};
    my $newpass_verify = $args->{p2};

    die "Unable to find account" unless $account;

    die "Passwords do not match" unless $newpass eq $newpass_verify;

    die "Old Password is incorrect" unless $self->get__password() eq $self->_encrypt_pass( $oldpass, $self );

    $self->set__password( $self->_encrypt_pass($newpass, $self) );
    return "Password Reset";

} #reset_password

sub reset_email {
    my( $self, $arg, $account ) = @_;
    $self->set_email( $arg );
    return "Updated email";
} #reset_email

1;

__END__
