package Yote::Login;

use strict;
use warnings;

use base 'Yote::Obj';


sub reset_email {
    my( $self, $data, $account ) = @_;
    my $email = $data->{email};
    my $pw = $data->{pw};

    die "Incorrect Password" unless $self->get__password() eq Yote::ObjProvider::encrypt_pass( $pw, $self );

    $self->set_email( $email );
    return "Updated email";
} #reset_email

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

    die "Old Password is incorrect" unless $self->get__password() eq Yote::ObjProvider::encrypt_pass( $oldpass, $self );

    $self->set__password( Yote::ObjProvider::encrypt_pass($newpass, $self) );
    return "Password Reset";

} #reset_password

sub is_root {
    my $self = shift;
    return $self->get__is_root();
} #is_root

#
# This is actually a no-op, but has the effect of giving the client any objects that have changed since the clients last call.
#
sub sync_all {}

sub upload_avatar {
    my( $self, $data ) = @_;
    $self->set_avatar( $data->{avatar} );
}

sub Avatar {
    my $self = shift;
    return $self->get_avatar();
}

1;

__END__

=head1 NAME

Yote::Login

=head1 DESCRIPTION

Each user gets a single login for the yote system. The Yote::Login objects are 
container objects that store state data for the users.

=head1 PUBLIC METHODS

=over 4

=item reset_email

Resets the email for this login taking a hash reference as an argument with the keys 'email' for the email,
'pw' for password. Returns 'Updated email'.

=item reset_password

Resets the password for this login taking a hash reference as an argument with the keys 'op' for old password, 
'p' for password and 'p2' for password verification. Returns 'Password Reset'.

=item UploadAvatar

Create a Yote::FileHelper object representing the avatar image. 
The file control name is 'avatar' that uploads the avatar image.

=item Avatar

Returns a Yote::FileHelper object representing the avatar image.

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut

