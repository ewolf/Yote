package Yote::Login;

###########################################################################
# A user gets one system wide login, and a separate account for each app. #
###########################################################################

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.04';

use base 'Yote::Obj';

sub is_root {
    my $self = shift;
    return $self->get__is_root();
} #is_root

sub is_master_root {
    my $self = shift;
    return $self->get__is_master_root();    
}

sub is_validated {
    my $self = shift;
    return $self->get__is_validated();
}

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

    die "Old Password is incorrect" unless $self->get__password() eq Yote::ObjProvider::encrypt_pass( $oldpass, $self->get_handle() );

    $self->set__password( Yote::ObjProvider::encrypt_pass($newpass, $self->get_handle()) );
    return "Password Reset";

} #reset_password


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

=item is_master_root

Returns true if the account is the original root account

=item is_root

Returns true if the account has root privileges.

=item is_validated

Returns true if the account has validated.

=item reset_password

Resets the password for this login taking a hash reference as an argument with the keys 'op' for old password, 
'p' for password and 'p2' for password verification. Returns 'Password Reset'.

=item upload_avatar

Create a Yote::FileHelper object representing the avatar image. 
The file control name is 'avatar' that uploads the avatar image.

=item Avatar

Returns a Yote::FileHelper object representing the avatar image.

=back

=head1 PUBLIC DATA FIELDS

=over 4

=item email

=item handle

=back

=head1 PRIVATE DATA FIELDS

=over 4

=item __created_ip

=item __is_master_root

=item __is_root

=item __time_created

=item _password

=back

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut

