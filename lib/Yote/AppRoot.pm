package Yote::AppRoot;

#
# Base class for all Yote applications.
#

use strict;
use warnings;

use Yote::Obj;
use Email::Valid;
use MIME::Base64;
use Yote::Account;
use Yote::YoteRoot;

use base 'Yote::Obj';

use vars qw($VERSION);
$VERSION = '0.087';

# ------------------------------------------------------------------------------------------
#      * INITIALIZATION *
# ------------------------------------------------------------------------------------------


#
# Intializes the account object passed in.
#
sub _init_account {}

#
# Override to use different classes for the account objects.
#
sub _new_account {
    return new Yote::Account();
}

# ------------------------------------------------------------------------------------------
#      * PUBLIC API Methods *
# ------------------------------------------------------------------------------------------


#
# Return the account object for this app.
#
sub account {
    my( $self, $data, $account ) = @_;
    return $account;
} #account

#
# Available to all apps. Used for verification and for cookie login.
#
sub token_login {
    my( $self, $t, undef, $env ) = @_;
    my $ip = $env->{ REMOTE_ADDR };
    if( $t =~ /(.+)\-(.+)/ ) {
        my( $uid, $token ) = ( $1, $2 );
        my $login = $self->_fetch( $uid );
        if( ref( $login ) && ref( $login ) ne 'HASH' && ref( $login ) ne 'ARRAY'
	    && $login->get__token() eq "${token}x$ip" ) {
	    return $login;
	}
    }
    return 0;
} #token_login

# ------------------------------------------------------------------------------------------
#      * Private Methods *
# ------------------------------------------------------------------------------------------



#
# This can be overridden and is where the app will send out a stylized email validation request to the person who made the account.
#
sub _validation_request {
    my( $self, $login ) = @_;

    my $root = Yote::Yote::fetch_root();


} #_validation_request

#
# Returns the account root attached to this AppRoot for the given account.
#
sub __get_account {
    my( $self, $login ) = @_;
    my $accts = $self->get__account_roots({});
    my $acct = $accts->{$login->{ID}};
    unless( $acct ) {
        $acct = $self->_new_account();
        $acct->set_login( $login );
	$acct->set_handle( $login->get_handle() );
        $accts->{$login->{ID}} = $acct;
	$self->_init_account( $acct );
    }
    return $acct;

} #__get_account

1;

__END__

=head1 NAME

Yote::AppRoot - Application Server Base Objects

=head1 DESCRIPTION

This is the root class for all Yote Apps. Extend it to create an App Object.

Each Web Application has a single container object as the entry point to that object which is an instance of the Yote::AppRoot class. 
A Yote::AppRoot extends Yote::Obj and provides some class methods and the following stub methods.


=head1 PUBLIC API METHODS

=over 4

=item account()

Returns the currently logged in account using this app.

=item token_login()

Returns a token that is used by the client and server to sync up data for the case of a user not being logged in.

=back

=head1 PUBLIC DATA FIELDS

=over 4

=item apps

This is a hash of app name to app object.

=back

=head1 PRIVATE DATA FIELDS

=over 4

=item _handles

A hash of handle to Yote::Login object for that user.

=item _emails

A hash of email address to Yote::Login object for that user.

=item _application_lib_directories

A list containing names of directories on the server that should be searched for Yote app classes and libraries.

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
