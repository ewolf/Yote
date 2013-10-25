package Yote::AppRoot;

#########################################
# Base class for all Yote applications. #
#########################################

use strict;
use warnings;

use Yote::Obj;
use Email::Valid;
use MIME::Base64;
use Yote::Account;
use Yote::YoteRoot;

use base 'Yote::RootObj';

use vars qw($VERSION);
$VERSION = '0.087';

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
# Used by the web app server to verify the login. Returns the login object belonging to the token.
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

###########################################################
# Messages meant to be overridden and customized per app. #
###########################################################

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



#######################################################
# Fixed ( should not be overridden ) utility methods. #
#######################################################

#
# Returns the account root attached to this AppRoot for the given account. Not meant to be overridden.
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
    die "Access Error" if $acct->get__is_disabled();
    
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

=head1 OVERRIDABLE METHODS

=over 4

=item _init_account( $acct )

This is called whenever a new account is created for this app. This can be overridden to perform any initialzation on the 
account.

=item _new_account()

This returns a new Yote::Account object to be used with this app. May be overridden to return a subclass of Yote::Account.

=back

=head1 PRIVATE DATA FIELDS

=over 4

=item _account_roots

This is a hash of login ID to account.

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
