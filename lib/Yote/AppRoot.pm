package Yote::AppRoot;

#########################################
# Base class for all Yote applications. #
#########################################

use strict;
use warnings;

use Yote::Obj;
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

sub create_login {
    my( $self, $args, $dummy, $env ) = @_;
    my( $handle, $email, $password ) = ( $args->{h}, $args->{e}, $args->{p} );

    if( $self->get_requires_email_validation() && ! $email ) {
	die "Must specify valid email";
    }

    my $root = Yote::YoteRoot::fetch_root();
    my $login = $root->_create_login( $handle, $email, $password, $env );

    if( $self->get_requires_email_validation() ) {
	my $rand_token = $root->_register_login_with_validation_token( $login );

	Yote::IO::Mailer::send_email( 
	    {
		to      => $email,
		from    => $self->get_login_email_from( 'yote@' . $self->get_host_name( `hostname` ) ),
		subject => $self->get_login_subject('Validate your Account'),
		msg     => $self->get_login_message_template(new Yote::SimpleTemplate({text=>'Welcome to ${app}, ${handle}. Click on this link to validate your email : ${link}'}))->fill( 
		    {
			handle => $handle,
			email  => $email,
			app    => $self->get_app_name( ref( $self ) ),
			link   => $self->get_validation_link_template(new Yote::SimpleTemplate(
									  {
									      text=>'${hosturl}/val.html?t=${t}'}))->fill( 
			    {
				t       => $rand_token,
				hosturl => $self->get_host_url('http://' . $self->get_host_name( `hostname` ) ),
			    } )
		    } )
	    } );
    } #requires validation

    return $login;
} #create_login

#
# Sends an email to the address containing a link to reset password.
#
sub recover_password {
    my( $self, $args ) = @_;

    my $email    = $args->{e};
    my $from_url = $args->{u};
    my $to_reset = $args->{t};

    my $login = $self->_hash_fetch( '_emails', $email );

    if( $login ) {
        my $now = time();
        if( $now - $login->get__last_recovery_time() > (60*15) ) { #need to wait 15 mins
            my $rand_token = int( rand 9 x 10 );
            my $recovery_hash = $self->get__recovery_logins({});
            my $times = 0;
            while( $recovery_hash->{$rand_token} && ++$times < 100 ) {
                $rand_token = int( rand 9 x 10 );
            }
            if( $recovery_hash->{$rand_token} ) {
                die "error recovering password";
            }
            $login->set__recovery_from_url( $from_url );
            $login->set__last_recovery_time( $now );
            $login->set__recovery_tries( $login->get__recovery_tries() + 1 );
            $recovery_hash->{$rand_token} = $login;
            my $link = "$to_reset?t=$rand_token";
	    my $sender = new Mail::Sender( {
		smtp => 'localhost',
		from => 'yote@localhost',
					   } );
	    $sender->MailMsg( { to => $email,
				 subject => 'Password Recovery',
				 msg => "<h1>Yote password recovery</h1> Click the link <a href=\"$link\">$link</a>",
			       } );


        }
	else {
            die "password recovery attempt failed";
        }
    }
    return "password recovery initiated";
} #recover_password

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

sub validate {
    my( $self, $token ) = @_;
    my $root = Yote::YoteRoot::fetch_root();
    return $root->_validate( $token );
} #validate

# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

###################################
# These methods may be overridden #
###################################

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

=item recover_password( { e : email, u : a_url_the_person_requested_recovery, t : reset_url_for_system } )

Causes an email with a recovery link sent to the email in question, if it is associated with an account.

Returns the currently logged in account using this app.

=item token_login()

Returns a token that is used by the client and server to sync up data for the case of a user not being logged in.

=item validate( rand_token )

Validates and returns the login specified by the random token.

=back

=head1 OVERRIDABLE METHODS

=over 4

=item _init_account( $acct )

This is called whenever a new account is created for this app. This can be overridden to perform any initialzation on the
account.

=item _new_account()

This returns a new Yote::Account object to be used with this app. May be overridden to return a subclass of Yote::Account.

=back

=head1 PUBLIC DATA FIELDS

=over 4

=item requires_email_validation

When true, an account will not work until email validation of the login is achieved.

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
