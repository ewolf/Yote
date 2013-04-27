package Yote::Account;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';

use base 'Yote::Messenger';

#
# This is actually a no-op, but has the effect of giving the client any objects that have changed since the clients last call.
#
sub sync_all {}

sub upload_avatar {
    my( $self, $data, $acct ) = @_;
    my $login = $acct->get_login();
    if( $login->get__password() eq Yote::ObjProvider::encrypt_pass( $data->{p}, $login ) ) {
	$self->set_avatar( $data->{avatar_file} );
	return "set avatar";
    }
    die "incorrect password";
}

1;

__END__

=head1 NAME

Yote::Account

=head1 DESCRIPTION 

This module is essentially meant to be used as is or extended.
Yote::Account is a base class for account objects. A user has different account object for each different app. 
The distinction between a Login and an account is that a user has exactly one system-wide Yote::Login but
a different Yote::Account object per application.

The Yote::Account object is a container intended to store any data that is relevant to a user for a particular app.

=head1 PUBLIC API METHODS

=over 4

=item upload_avatar

This is called with a file uploaded POST where the file input name is 'avatar_file'.

=item sync_all

This method is actually a no-op, but has the effect of syncing the state of client and server.

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
