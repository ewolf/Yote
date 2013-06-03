package Yote::YoteRoot;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.05';

no warnings 'uninitialized';

use Yote::Cron;
use Yote::Login;
use Mail::Sender;
use MIME::Lite;

use base 'Yote::AppRoot';

our $HANDLE_CACHE = {};
our $EMAIL_CACHE = {};


# ------------------------------------------------------------------------------------------
#      * INIT METHODS *
# ------------------------------------------------------------------------------------------
sub _init {
    my $self = shift;
    $self->set__apps({});
    $self->set__handles({});
    $self->set__emails({});
    $self->set__crond( new Yote::Cron() );
    $self->set__application_lib_directories( [] );
} #_init


# ------------------------------------------------------------------------------------------
#      * PUBLIC METHODS *
# ------------------------------------------------------------------------------------------


#
# Creates a login with credentials provided
#   (client side) use : create_login({h:'handle',e:'email',p:'password'});
#             returns : { l => login object, t => token }
#
sub create_login {
    my( $self, $args, $dummy, $env ) = @_;

    #
    # validate login args. Needs handle (,email at some point)
    #
    my( $handle, $email, $password ) = ( $args->{h}, $args->{e}, $args->{p} );
    if( $handle ) {
	my $lc_handle = lc( $handle );
        if( $HANDLE_CACHE->{$lc_handle} || $self->_hash_has_key( '_handles', $lc_handle ) ) {
            die "handle already taken";
        }
        if( $email ) {
            if( $EMAIL_CACHE->{$email} || $self->_hash_has_key( '_emails', $email ) ) {
                die "email already taken";
            }
            unless( Email::Valid->address( $email ) ) {
                die "invalid email '$email'";
            }
        }
        unless( $password ) {
            die "password required";
        }

	$EMAIL_CACHE->{$email}   = 1 if $email;
	$HANDLE_CACHE->{$lc_handle} = 1;

        my $new_login = new Yote::Login();

	$new_login->set__is_root( 0 );
        $new_login->set_handle( $handle );
        $new_login->set_email( $email );
	my $ip = $env->{REMOTE_ADDR};
        $new_login->set__created_ip( $ip );

        $new_login->set__time_created( time() );

        $new_login->set__password( Yote::ObjProvider::encrypt_pass($password, $new_login->get_handle()) );

	$self->_hash_insert( '_emails', $email, $new_login ) if $email;
	$self->_hash_insert( '_handles', $lc_handle, $new_login );
	
        return { l => $new_login, t => $self->_create_token( $new_login, $ip ) };
    } #if handle

    die "no handle given";

} #create_login
#
# Fetches objects by id list
#
sub fetch {
    my( $self, $data, $account, $env ) = @_;
    die "Access Error" unless Yote::ObjManager::allows_access( $data, $self, $account ? $account->get_login() : undef, $env->{GUEST_TOKEN} );
    if( ref( $data ) eq 'ARRAY' ) {
	my $login = $account->get_login();
	return [ map { Yote::ObjProvider::fetch( $_ ) } grep { $Yote::ObjProvider::LOGIN_OBJECTS->{ $login->{ID} }{ $_ } } @$data ];
    } 
    return [ Yote::ObjProvider::fetch( $data ) ];

} #fetch
#
# Returns a list starting with the app object, followed by objects that the app wants to bring with
#
sub fetch_app_by_class {
    my( $self, $data ) = @_;
    my $app = $self->get__apps({})->{$data};
    unless( $app ) {
        eval ("use $data");
        die $@ if $@;
        $app = $data->new();
        $self->get__apps()->{$data} = $app;
    }
    return $app;
} #fetch_app_by_class


#
# Returns this root object.
#
sub fetch_root {
    my $root = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    unless( $root ) {
	$root = new Yote::YoteRoot();
	Yote::ObjProvider::stow( $root );
    }
    return $root;
}

#
# Returns a token for non-logging in use.
#
sub guest_token {
    my $ip = shift;
    my $token = int( rand 9 x 10 );
    $Yote::ObjProvider::IP_TO_GUEST_TOKEN->{$ip} = {$token => time()}; # @TODO - make sure this and the LOGIN_OBJECTS cache is purged regularly. cron maybe?
    $Yote::ObjProvider::GUEST_TOKEN_OBJECTS->{$token} = {};  #memory leak? @todo - test this

    # @TODO write a Cache class to hold onto objects, with an interface like fetch( obj_id, login, guest_token )

    return $token;
} #guest_token

#
# Validates that the given credentials are given
#   (client side) use : login({h:'handle',p:'password'});
#             returns : { l => login object, t => token }
#
sub login {
    my( $self, $data, $dummy, $env ) = @_;

    if( $data->{h} ) {
	my $lc_h = lc( $data->{h} );
	my $ip = $env->{ REMOTE_ADDR };
        my $login = $self->_hash_fetch( '_handles', $lc_h );
        if( $login && ($login->get__password() eq Yote::ObjProvider::encrypt_pass( $data->{p}, $login->get_handle()) ) ) {
	    Yote::ObjManager::clear_login( $login, $env->{GUEST_TOKEN} );
            return { l => $login, t => $self->_create_token( $login, $ip ) };
        }
    }
    die "incorrect login";
} #login

sub logout {
    my( $self, $data, $acct ) = @_;
    if( $acct ) {
	my $login = $acct->get_login();
	$login->set__token();
    }
} #logout
#
# Used to wipe and reset a whole app's data. Use with caution
# and can only be used by the superuser.
#
sub purge_app {
    my( $self, $app_name, $account ) = @_;
    if( $account->get_login()->get__is_root() ) {
	my $apps = $self->get__apps();
	my $app = delete $apps->{ $app_name };
	$self->add_to__purged_apps( $app );
	return "Purged '$app_name'";
    }
    die "Permissions Error";
} #purge_app




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
	    print STDERR Data::Dumper->Dump(["RECOVERY LINK $link"]);
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
# reset by a recovery link.
#
sub recovery_reset_password {
    my( $self, $args ) = @_;

    my $newpass        = $args->{p};
    my $newpass_verify = $args->{p2};

    die "Passwords don't match" unless $newpass eq $newpass_verify;
    
    my $rand_token     = $args->{t};
    
    my $recovery_hash = $self->get__recovery_logins({});
    my $login = $recovery_hash->{$rand_token};
    if( $login ) {
        my $now = $login->get__last_recovery_time();
        delete $recovery_hash->{$rand_token};
        if( ( time() - $now ) < 3600 * 24 ) { #expires after a day
            $login->set__password( Yote::ObjProvider::encrypt_pass( $newpass, $login->get_handle() ) );
            return $login->get__recovery_from_url();
        }
    }
    die "Recovery Link Expired or not valid";

} #recovery_reset_password


#
# Removes a login. Need not only to be logged in, but present all credentials
#   (client side) use : remove_login({h:'handle',e:'email',p:'password'});
#             returns : "deleted account"
#
sub remove_login {
    my( $self, $args, $acct, $env ) = @_;
    my $login = $acct->get_login();


    if( $login && 
        Yote::ObjProvider::encrypt_pass($args->{p}, $login->get_handle()) eq $login->get__password() &&
        $args->{h} eq $login->get_handle() &&
        $args->{e} eq $login->get_email() &&
        ! $login->get_is__first_login() ) 
    {
        delete $self->get__handles()->{$args->{h}};
        delete $self->get__emails()->{$args->{e}};
	delete $HANDLE_CACHE->{$args->{h}};
	delete $EMAIL_CACHE->{$args->{e}};
        $self->add_to__removed_logins( $login );
        return "deleted account";
    } 
    die "unable to remove account";
    
} #remove_login

# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

#
# Makes sure there is a root account with the given credentials.
#
sub _check_root {
    my( $self, $root_name, $encr_passwd ) = @_;
    
    my $lc_handle = lc( $root_name );

    my $root_login = $self->_hash_fetch( '_handles', $lc_handle );
    
    unless( $root_login ) {
	$root_login = new Yote::Login();
	$root_login->set_handle( $root_name );
	$root_login->set__is_root( 1 );

        $root_login->set__time_created( time() );

	$self->_hash_insert( '_handles', $lc_handle, $root_login );	
    }

    $root_login->set__password( $encr_passwd );
    
} #_create_root

#
# Create token and store with the account and return it.
#
sub _create_token {
    my( $self, $login, $ip ) = @_;
    my $token = int( rand 9 x 10 );
    $login->set__token( $token."x$ip" );
    return $login->{ID}.'-'.$token;
}

1;

__END__

=head1 NAME

Yote::YoteRoot

=head1 DESCRIPTION

The yote root is the main app of the class. It is also always object id 1 and sits at the head of the yote data tree. Yote::YoteRoot is a subclass of Yote::AppRoot.

=head1 DATA 

=head1 PUBLIC API METHODS

=over 4

=item fetch( id_list )

Returns the list of the objects to the client provided the client is authroized to receive them.

=item fetch_app_by_class( package_name )

Returns the app object singleton of the given package name.

=item fetch_root( package_name )

Returns the singleton root object. It creates it if it has not been created.

=item guest_token

Creates and returns a guest token, associating it with the calling IP address.

=item login( { h: handle, p : password } )

Attempts to log the account in with the given credentials. Returns a data structre with 
the login token and the login object.

=item logout

Invalidates the tokens of the currently logged in user.

=item new 

=item init - takes a hash of args, passing them to a new Yote::SQLite object and starting it up.

=item purge_app

This method may only be invoked by a login with the root bit set. This clears out the app entirely.

=item recover_password( { e : email, u : a_url_the_person_requested_recovery, t : reset_url_for_system } )

Causes an email with a recovery link sent to the email in question, if it is associated with an account.

=item recovery_reset_password( { p : newpassword, p2 : newpasswordverify, t : recovery_token } )

Resets the password ( kepts hashed in the database ) for the account that the recovery token belongs to.
Returns the url_the_person_requested_recovery that was given in the recover_password call.

=item remove_login( { h : handle, e : email, p : password } )

Purges the login account from the system if its credentials are verified. It moves the account to a special removed logins hidden field under the yote root.

=item create_login( args )

Create a login with the given client supplied args : h => handle, e => email, p => password.
This checks to make sure handle and email address are not already taken. 
This is invoked by the javascript call $.yote.create_login( handle, password, email )

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
