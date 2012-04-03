package Yote::YoteRoot;

use Yote::Login;

use base 'Yote::AppRoot';

use strict;

sub init {
    my $self = shift;
    $self->set_apps({});
    $self->set_app_alias({});
    $self->set__handles({});
    $self->set__emails({});
} #init

sub fetch_app_by_class {
    my( $self, $data ) = @_;
    my $app = $self->get_apps()->{$data};
    unless( $app ) {
        eval("use $data");
        die $@ if $@;
        $app = $data->new();
        $self->get_apps()->{$data} = $app;
    }
    return $app;
} #fetch_app_by_class

#
# Returns this root object.
#
sub fetch_root {
    return Yote::ObjProvider::fetch( 1 );
}

#
# Fetches object by id
#
sub fetch {
    my( $self, $data, $account ) = @_;
    my $obj = Yote::ObjProvider::fetch( $data );
    if( $self->_account_can_access( $account, $obj ) ) {
        return $obj;
    }
    die "Access Error";
} #fetch

#
# Validates that the given credentials are given
#   (client side) use : login({h:'handle',p:'password'});
#             returns : { l => login object, t => token }
#
sub login {
    my( $self, $data ) = @_;

    my $ip = $data->{_ip};

    if( $data->{h} ) {
        my $login = Yote::ObjProvider::xpath("/_handles/$data->{h}");
        if( $login && ($login->get__password() eq $self->_encrypt_pass( $data->{p}, $login) ) ) {
            return { l => $login, t => $self->_create_token( $login, $ip ) };
        }
    }
    die "incorrect login";
} #login

sub logout {
    my( $self, $data, $acct ) = @_;
    my $login = $acct->get_login();
    $login->set_token();
} #logout

#
# Creates a login with credentials provided
#   (client side) use : create_login({h:'handle',e:'email',p:'password'});
#             returns : { l => login object, t => token }
#
sub create_login {
    my( $self, $args ) = @_;

    my $ip = $args->{_ip};

    #
    # validate login args. Needs handle (,email at some point)
    #
    my( $handle, $email, $password ) = ( $args->{h}, $args->{e}, $args->{p} );
    if( $handle ) {
        if( Yote::ObjProvider::xpath("/_handles/$handle") ) {
            die "handle already taken";
        }
        if( $email ) {
            if( Yote::ObjProvider::xpath("/_emails/$email") ) {
                die "email already taken";
            }
            unless( Email::Valid->address( $email ) ) {
                die "invalid email";
            }
        }
        unless( $password ) {
            die "password required";
        }
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
        $new_login->set__created_ip( $ip );

        $new_login->set__time_created( time() );

        $new_login->set__password( $self->_encrypt_pass($password, $new_login) );

        my $logins = $self->get__handles();
        $logins->{ $handle } = $new_login;
        my $emails = $self->get__emails();
        $emails->{ $email } = $new_login;

        return { l => $new_login, t => $self->_create_token( $new_login, $ip ) };
    } #if handle

    die "no handle given";

} #create_login

#
# Removes a login. Need not only to be logged in, but present all credentials
#   (client side) use : remove_login({h:'handle',e:'email',p:'password'});
#             returns : "deleted account"
#
sub remove_login {
    my( $self, $args, $acct ) = @_;

    my $ip = $args->{_ip};

    my $login = $acct->get_login();

    if( $login && 
        $self->_encrypt_pass($args->{p}, $login) eq $login->get__password() &&
        $args->{h} eq $login->get_handle() &&
        $args->{e} eq $login->get_email() &&
        ! $login->get_is__first_login() ) 
    {
        delete $self->get__handles()->{$args->{h}};
        delete $self->get__emails()->{$args->{e}};
        $self->add_to_removed_logins( $login );
        return "deleted account";
    } 
    die "unable to remove account";
    
} #remove_login


#
# Sends an email to the address containing a link to reset password.
#
sub recover_password {
    my( $self, $args ) = @_;

    my $email    = $args->{e};
    my $from_url = $args->{u};
    my $to_reset = $args->{t};

    my $login = Yote::ObjProvider::xpath( "/emails/$email" );
    if( $login ) {
        my $now = time();
        if( $now - $login->get__last_recovery_time() > (60*15) ) { #need to wait 15 mins
            my $rand_token = int( rand 9 x 10 );
            my $recovery_hash = $self->get_recovery_logins({});
            my $times = 0;
            while( $recovery_hash->{$rand_token} && ++$times < 100 ) {
                $rand_token = int( rand 9 x 10 );
            }
            if( $recovery_hash->{$rand_token} ) {
                die "error recovering password";
            }
            $login->set__recovery_token( $rand_token );
            $login->set_recovery_from_url( $from_url );
            $login->set_last_recovery_time( $now );
            $login->set_recovery_tries( $login->get_recovery_tries() + 1 );
            $recovery_hash->{$rand_token} = $login;
            my $link = "$to_reset?t=$rand_token&p=".MIME::Base64::encode($from_url);
            # email
            my $msg = MIME::Lite->new(
                From    => 'yote@127.0.0.1',
                To      => $email,
                Subject => 'Password Recovery',
                Type    => 'text/html',
                Data    => "<h1>Yote password recovery</h1> Click the link <a href=\"$link\">$link</a>",
                );
            $msg->send();
        } else {
            die "password recovery attempt failed";
        }
    }
    return "password recovery initiated";
} #recover_password

#
# Can either be reset by logged in account, or by a recovery link.
#
sub reset_password {
    my( $self, $args ) = @_;

    my $newpass        = $args->{p};
    my $newpass_verify = $args->{p2};

    die "Passwords don't match" unless $newpass eq $newpass_verify;
    
    my $rand_token     = $args->{t};
    
    my $recovery_hash = $self->get_recovery_logins({});
    my $acct = $recovery_hash->{$rand_token};
    if( $acct ) {
        my $login = $acct->get_login();
        my $now = $acct->get_last_recovery_time();
        delete $recovery_hash->{$rand_token};
        if( ( time() - $now ) < 3600 * 24 ) { #expires after a day
            $login->set__password( $self->_encrypt_pass( $newpass, $login ) );
            $login->set__recovery_token( undef );
            return "Password Reset";
        }
    }
    die "Recovery Link Expired or not valid";

} #reset_password


#
# Create token and store with the account and return it.
#
sub _create_token {
    my( $self, $login, $ip ) = @_;
    my $token = int( rand 9 x 10 );
    $login->set_token( $token."x$ip" );
    return $login->{ID}.'+'.$token;
}

1;
