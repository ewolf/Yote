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

#
# Create login.
#
sub create_login {
    my( $self, $args, $dummy, $env ) = @_;

    my( $handle, $email, $password ) = ( $args->{h}, $args->{e}, $args->{p} );
    if( $handle ) {
	my $root = Yote::Yote::fetch_root();
	my $lc_handle = lc( $handle );
        if( $Yote::YoteRoot::HANDLE_CACHE->{$lc_handle} || $root->_hash_has_key( '_handles', $lc_handle ) ) {
            die "handle already taken";
        }
        if( $email ) {
            if( $Yote::YoteRoot::EMAIL_CACHE->{$email} || $root->_hash_has_key( '_emails', $email ) ) {
                die "email already taken";
            }
            unless( Email::Valid->address( $email ) ) {
                die "invalid email '$email'";
            }
        }
        unless( $password ) {
            die "password required";
        }

	$Yote::YoteRoot::EMAIL_CACHE->{$email}      = 1 if $email;
	$Yote::YoteRoot::HANDLE_CACHE->{$lc_handle} = 1;

        my $new_login = new Yote::Login();

	$new_login->set__is_root( 0 );
        $new_login->set_handle( $handle );
        $new_login->set_email( $email );
	my $ip = $env->{REMOTE_ADDR};
        $new_login->set__created_ip( $ip );

        $new_login->set__time_created( time() );

        $new_login->set__password( Yote::ObjProvider::encrypt_pass($password, $new_login->get_handle()) );

	$root->_hash_insert( '_emails', $email, $new_login ) if $email;
	$root->_hash_insert( '_handles', $lc_handle, $new_login );

	$self->_validation_request( $new_login );
	
        return { l => $new_login, t => $root->_create_token( $new_login, $ip ) };
    } #if handle

    die "no handle given";
} #create_login

#
# Request password email be sent.
#
sub recover_password {
    my( $self, $args ) = @_;
    
} #recover_password

#
# reset her password.
# 
sub reset_password {
    my( $self, $args ) = @_;

} #reset_password

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

=item create_login( args )

Create a login with the given client supplied args : h => handle, e => email, p => password.
This checks to make sure handle and email address are not already taken. 
This is invoked by the javascript call $.yote.create_login( handle, password, email )

=item recover_password( { e : email, u : a_url_the_person_requested_recovery, t : reset_url_for_system } )

Causes an email with a recovery link sent to the email in question, if it is associated with an account.

=item reset_password( { p : newpassword, p2 : newpasswordverify, t : recovery_token } )

Resets the password of the login for this account.

=item recovery_reset_password( { p : newpassword, p2 : newpasswordverify, t : recovery_token } )

Resets the password ( kepts hashed in the database ) for the account that the recovery token belongs to.
Returns the url_the_person_requested_recovery that was given in the recover_password call.

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
