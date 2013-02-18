package Yote::YoteRoot;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Cron;
use Yote::Login;
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
        if( $HANDLE_CACHE->{$handle} || Yote::ObjProvider::xpath("/_handles/$handle") ) {
            die "handle already taken";
        }
        if( $email ) {
            if( $EMAIL_CACHE->{$email} || Yote::ObjProvider::xpath("/_emails/$email") ) {
                die "email already taken";
            }
            unless( Email::Valid->address( $email ) ) {
                die "invalid email";
            }
        }
        unless( $password ) {
            die "password required";
        }

	$EMAIL_CACHE->{$email}   = 1;
	$HANDLE_CACHE->{$handle} = 1;

        my $new_login = new Yote::Login();

        #
        # check to see how many logins there are. If there are none,
        # give the first root access.
        #
        if( Yote::ObjProvider::xpath_count( "/_handles" ) == 0 ) {
            $new_login->set__is_root( 1 );
            $new_login->set__is_first_login( 1 );
        } else {
            $new_login->set__is_root( 0 );
        }
        $new_login->set_handle( $handle );
        $new_login->set_email( $email );
	my $ip = $env->{REMOTE_ADDR};
        $new_login->set__created_ip( $ip );

        $new_login->set__time_created( time() );

        $new_login->set__password( Yote::ObjProvider::encrypt_pass($password, $new_login) );

	Yote::ObjProvider::xpath_insert( "/_emails/$email", $new_login );
	Yote::ObjProvider::xpath_insert( "/_handles/$handle", $new_login );
	
        return { l => $new_login, t => $self->_create_token( $new_login, $ip ) };
    } #if handle

    die "no handle given";

} #create_login
#
# Fetches object by id
#
sub fetch {
    my( $self, $data, $account, $env ) = @_;
    die "Access Error" unless Yote::ObjManager::knows_dirty( ref( $data ) ? $data : [ $data ], undef, $account ? $account->get_login() : undef, $env->{GUEST_TOKEN} );
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
        eval("use $data");
        die $@ if $@;
        $app = $data->new();
        $self->get__apps()->{$data} = $app;
    }
    return [$app,@{$app->_extra_fetch()}];
} #fetch_app_by_class


#
# Returns this root object.
#
sub fetch_root {
    my $root = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    unless( $root ) {
	$root = new Yote::YoteRoot();
    }
    return $root;
}

sub flush_credential_cache {
    $EMAIL_CACHE = {};
    $HANDLE_CACHE = {};
} #flush_credential_cache

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
	my $ip = $env->{ REMOTE_ADDR };
        my $login = Yote::ObjProvider::xpath("/_handles/$data->{h}");
        if( $login && ($login->get__password() eq Yote::ObjProvider::encrypt_pass( $data->{p}, $login) ) ) {
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
    my( $self, $data, $account ) = @_;
    if( $account->get__is_root() ) {
	$self->_purge_app( $data );
	return "Purged '$data'";
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

    my $login = Yote::ObjProvider::xpath( "/_emails/$email" );

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
	    use Mail::Sender;
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
            $login->set__password( Yote::ObjProvider::encrypt_pass( $newpass, $login ) );
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
        Yote::ObjProvider::encrypt_pass($args->{p}, $login) eq $login->get__password() &&
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
# Create token and store with the account and return it.
#
sub _create_token {
    my( $self, $login, $ip ) = @_;
    my $token = int( rand 9 x 10 );
    $login->set__token( $token."x$ip" );
    return $login->{ID}.'-'.$token;
}

sub _purge_app {
    my( $self, $app ) = @_;
    my $apps = $self->get__apps();
    return delete $apps->{$app};
} #_purge_app


1;

__END__

=head1 NAME

Yote::YoteRoot

=head1 DESCRIPTION

The yote root is the main app of the class. It is also always object id 1 and sits at the head of the yote data tree. Yote::YoteRoot is a subclass of Yote::AppRoot.

=head1 DATA 

=head1 INIT METHODS

=over 4

=item new 

=item init - takes a hash of args, passing them to a new Yote::SQLite object and starting it up.

=back

=head1 PUBLIC API METHODS

=over 4

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
