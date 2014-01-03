package Yote::Account;

###########################################################################
# Each user has one account per App. Each user has one system wide login. #
###########################################################################

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.05';

use base 'Yote::Obj';

use Yote::UserObj;

sub upload_avatar {
    my( $self, $data, $acct ) = @_;
    my $login = $acct->get_login();
    if( $login->get__password() eq Yote::ObjProvider::encrypt_pass( $data->{p}, $login->get_handle() ) ) {
	$self->set_avatar( $data->{avatar_file} );
	return "set avatar";
    }
    die "incorrect password";
} #upload_avatar

sub is_root {
    my $self = shift;
    return $self->get_login()->get__is_root();
} #is_root

sub is_master_root {
    my $self = shift;
    return $self->get_login()->get__is_master_root();    
}

sub new_user_obj {
    my( $self, $data, $acct ) = @_;
    my $ret = new Yote::UserObj( ref( $data ) ? $data : undef );
    $ret->set___creator( $acct );
    return $ret;
} #new_user_obj

1;

__END__

=head1 NAME

Yote::Account

=head1 DESCRIPTION 

The Yote::Account object is a container intended to store any data that is relevant to a user for a particular app.
A single user will have one account per app, but only one systemwide login.

=head1 PUBLIC API METHODS

=over 4

=item upload_avatar

This is called with a file uploaded POST where the file input name is 'avatar_file'.

=item is_root

Called to reveal if the login behind this account is a root login.

=item is_master_root

Returns trus if the account is the original root account

=item new_user_obj( optional_data_hash )

Returns a new user yote object, initialized with the optional has reference.

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
