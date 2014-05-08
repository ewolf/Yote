package Yote::AppRoot;

#########################################
# Base class for all Yote applications. #
#########################################

use strict;
use warnings;

no warnings 'uninitialized';

use File::Slurp;
use MIME::Base64;

use Yote::Account;
use Yote::Obj;
use Yote::RootObj;
use Yote::SimpleTemplate;
use Yote::YoteRoot;

use parent 'Yote::RootObj';

use vars qw($VERSION);
$VERSION = '0.088';

sub _init {
    my $self = shift;
    my $hn = `hostname`;
    chomp $hn;

    $self->set_app_name( ref( $self ) );
    $self->set_host_name( $hn );
    $self->set_host_url( "http://$hn" );
    $self->set_validation_email_from( 'yote@' . $hn );
    $self->set_validation_link_template(new Yote::SimpleTemplate( { text=>'${hosturl}/val.html?t=${t}&app=${app}' } ) );
    $self->set_validation_message_template(new Yote::SimpleTemplate({text=>'Welcome to ${app}, ${handle}. Click on this link to validate your email : ${link}'}));
    $self->set_validation_subject_template(new Yote::SimpleTemplate( { text => 'Validate Your Account' } ) );

    $self->set_recovery_email_from( 'yote@' . $hn );
    $self->set_recovery_subject_template(new Yote::SimpleTemplate( { text => 'Recover Your Account' } ) );
    $self->set_recovery_link_template(new Yote::SimpleTemplate( { text => '${hosturl}/recover.html?t=${t}&app=${app}' } ) );
    $self->set_recovery_message_template(new Yote::SimpleTemplate({text=>'Click on <a href="${link}">${link}</a> to recover your account' } ) );

    $self->set__attached_objects( {} ); # field -> obj parings, set aside here as a duplicate data structure to track items that may be editable on the admin page

    $self->SUPER::_init();
} #_init

sub _load {
    my $self = shift;
    $self->get__attached_objects( {} ); # field -> obj parings, set aside here as a duplicate data structure to track items that may be editable on the admin page
}

sub precache {
    my( $self, $data, $account ) = @_;
} #_precache

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

    if( $self->get_requires_validation() && ! $email ) {
	die "Must specify valid email";
    }

    my $root = Yote::YoteRoot::fetch_root();
    my $login = $root->_create_login( $handle, $email, $password, $env );

    if( $self->get_requires_validation() ) {
	my $rand_token = $root->_register_login_with_validation_token( $login );
	my $link = $self->get_validation_link_template()->_fill( {
	    t       => $rand_token,
	    hosturl => $self->get_host_url(),
								 } );
	my $context = {
	    handle => $handle,
	    email  => $email,
	    app    => $self->get_app_name( ref( $self ) ),
	    link   => $link,
	};

	Yote::IO::Mailer::send_email(
	    {
		to      => $email,
		from    => $self->get_validation_email_from( 'yote@' . $self->get_host_name() ),
		subject => $self->get_validation_subject_template()->_fill( $context ),
		msg     => $self->get_validation_message_template()->_fill( $context ),
	    } );
    } #requires validation

    return { l => $login, t => $root->_create_token( $login, $env->{REMOTE_ADDR} ) };
} #create_login

#
#
#
sub do_404 {
    my $self = shift;
    return ( 404, $self->get_error_page() );
} #do_404

#
# TODO: maybe rather than app_name and DEfAULT, have a html_root and html_root_default fields
# Returns response code and response.
#
sub fetch_page {
    my( $self, $url ) = @_;
    my $node = $self->_hash_fetch( '_pages', $url );
    my $file_loc = "$ENV{YOTE_ROOT}/html/".$self->get_app_name()."/$url";
    my $app_default_loc = $self->get_app_default_loc();
    my $default_file_loc = defined( $app_default_loc ) ? "$ENV{YOTE_ROOT}/html/$app_default_loc" : undef;
    if( -e $file_loc ) {
	if( $node ) {
	  # check to see which is more recent. if the file is, then set the current version of the node to the file unless
	  # the node version is locked.
	  my $file_mod_time;
	  my $last_updated = $node->get_last_updated();
	  if( $file_mod_time > $last_updated ) {
	    my $html = read_file( $url );
	    if( ! $node->get_version_locked() ) {
	      $node->set_current_version_number( $node->_count( 'versions' ) );
	      $node->add_to_versions( $html );
	      $node->set_current_version( $html );
	    }
	    return 200, $html;
	  }
	  elsif( $file_mod_time < $last_updated ) {
	    my $html = $node->get_current_version();
	    write_file( $url, $html );
	    return 200, $html;
	  }
	  else {
	    return 200, $node->get_current_version();
	  }
	}
	else {
	    #create a new node
 	    my $html = read_file( $file_loc );
	    $self->_hash_insert( '_pages',
				 $url,
				 $node = new Yote::RootObj( { current_version => $html,
							      versions        => [ $html ],
							      last_updated    => time } ) );
	    return $html;
	}
    }
    elsif( $node ) {
	my $html = $node->get_current_version();
	write_file( $file_loc, $html );
	return 200, $html;
    }
    elsif( $default_file_loc && -e $default_file_loc ) {
	return 200, read_file( $default_file_loc );
    }
    else {
	return 404, $self->do_404();
    }
} #fetch_page

#
# Sends an email to the address containing a link to reset password.
#
sub recover_password {
    my( $self, $email ) = @_;

    my $root = Yote::YoteRoot::fetch_root();
    my $login = $root->_hash_fetch( '_emails', $email );
    if( $login ) {
        my $now = time();
        unless( $login || ( $now - $login->get__last_recovery_time() ) < (60*15) ) { #need to wait 15 mins
            die "password recovery attempt failed";
        }
	else {
            my $rand_token = int( rand 9 x 10 );
            my $recovery_hash = $root->get__recovery_logins({});
            my $times = 0;
            while( $recovery_hash->{$rand_token} && ++$times < 100 ) {
                $rand_token = int( rand 9 x 10 );
            }
            if( $recovery_hash->{$rand_token} ) {
                die "error recovering password";
            }

	    $login->set__recovery_token( $rand_token );
            $login->set__last_recovery_time( $now );
            $login->set__recovery_tries( $login->get__recovery_tries() + 1 );

            $recovery_hash->{$rand_token} = $login;

	    my $link = $self->get_recovery_link_template()->_fill(
		{
		    t       => $rand_token,
		    hosturl => $self->get_host_url(),
		    app     => ref( $self ),
		} );

	    my $context = {
		handle => $login->get_handle(),
		email  => $email,
		app    => $self->get_app_name(),
		link   => $link,
		app    => ref( $self ),
	    };
	    Yote::IO::Mailer::send_email(
		{
		    to      => $email,
		    from    => $self->get_recovery_email_from(),
		    subject => $self->get_recovery_subject_template()->_fill( $context ),
		    msg     => $self->get_recovery_message_template()->_fill( $context ),
		} );
        }
    } #if login
    return "password recovery initiated";
} #recover_password

#
# reset by a recovery link.
#
sub recovery_reset_password {
    my( $self, $args ) = @_;

    my $root = Yote::YoteRoot::fetch_root();
    my $newpass        = $args->{p};
    my $rand_token     = $args->{t};
    my $recovery_hash  = $root->get__recovery_logins({});
    my $login = $recovery_hash->{$rand_token};

    if( $login ) {
        my $now = $login->get__last_recovery_time();
        delete $recovery_hash->{$rand_token};
        if( ( time() - $now ) < 3600 * 24 ) { #expires after a day
            $login->set__password( Yote::ObjProvider::encrypt_pass( $newpass, $login->get_handle() ) );
	    $login->set__is_validated(1);
            return $login->get__recovery_from_url();
        }
    }
    die "Recovery Link Expired or not valid";

} #recovery_reset_password

sub remove_login {
    my( $self, $args, $acct, $env ) = @_;
    my $root = Yote::YoteRoot::fetch_root();
    return $root->_remove_login( $args->{ l }, $args->{ p }, $acct );
} #remove_login

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
    return;
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
    my $acct = $self->_hash_fetch( '_account_roots', $login->{ID} );
    unless( $acct ) {
        $acct = $self->_new_account();
        $acct->set_login( $login );
	$acct->set_handle( $login->get_handle() );
	$self->_hash_insert( '_account_roots', $login->{ID}, $acct );
	$self->_hash_insert( '_account_handles', lc( $login->get_handle() ), $acct );
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


=item create_login( args )

Create a login with the given client supplied args : h => handle, e => email, p => password.
This checks to make sure handle and email address are not already taken.
This is invoked by the javascript call $.yote.create_login( handle, password, email )

=item precache

Meant to be overridden. Returns all data to the client or html page that the app in order to not need lazy loading.

=item recover_password( { e : email, u : a_url_the_person_requested_recovery, t : reset_url_for_system } )

Causes an email with a recovery link sent to the email in question, if it is associated with an account.

Returns the currently logged in account using this app.

=item recovery_reset_password( { p : newpassword, p2 : newpasswordverify, t : recovery_token } )

Resets the password ( kepts hashed in the database ) for the account that the recovery token belongs to.
Returns the url_the_person_requested_recovery that was given in the recover_password call.

=item remove_login( { h : handle, e : email, p : password } )

Purges the login account from the system if its credentials are verified. It moves the account to a special removed logins hidden field under the yote root.

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

=item requires_validation

When true, an account will not work until validation of the login is achieved, through email or other means.

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
