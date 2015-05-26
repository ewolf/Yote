package Yote::Root;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.053';

no warnings 'uninitialized';

use Yote;
use Yote::Cron;
use Yote::Login;
use Yote::RootObj;
use Yote::SimpleTemplate;
use Yote::UserObj;

use Email::Valid;

use parent 'Yote::AppRoot';

#
# Used by Yote::ObjManager. If true, it won't mark things dirty. This is
# for the case where the Root is instantiated for the first time.
#
$Yote::Root::ROOT_INIT = 0;
our $ALLOWS_REV = {};
our $ALLOWS = {};
our $DIRTY = {};
our $REGISTERED_CONTAINERS = {};
our $IP_TO_GUEST_TOKEN = {};


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
    $self->set__validations( {} );
    $self->SUPER::_init();
} #_init

# ------------------------------------------------------------------------------------------
#      * PUBLIC METHODS *
# ------------------------------------------------------------------------------------------
sub admin_prefetch {
    my( $self, $data, $acct ) = @_;
    if( $acct && $acct->is_root() ) {
        my $cron = $self->_cron();
        my $ret = $cron->prefetch( undef, $acct );
        return {
            cron    => $cron,
            other   => $ret,
            handles => $self->get__handles({}),
            apps    => $self->get__apps({}),
        };
    }    
} #admin_prefect


# returns cron object for root
sub cron {
    my( $self, $data, $acct ) = @_;
    if( $acct && $acct->is_root() ) {
        return $self->_cron();
    }
    die "Permissions Error";
} #cron
sub _cron {
    my $self = shift;
    my $c = $self->get__crond();
    unless( $c ) {
        $c = new Yote::Cron();
        $self->set__crond( $c );
    }
    return $c;
}

sub disable_account {
    my( $self, $account_to_be_disabled, $logged_in_account ) = @_;
    die "Access Error" unless $logged_in_account->get_login()->is_root();
    die "Cannot disable master root account" if $account_to_be_disabled->get_login()->get__is_master_root();
    $account_to_be_disabled->set__is_disabled( 1 );
} #disable_account

sub disable_login {
    my( $self, $login_to_be_disabled, $logged_in_account ) = @_;
    die "Access Error" unless $logged_in_account->get_login()->is_root();
    die "Cannot disable master root login" if $login_to_be_disabled->get__is_master_root();
    $login_to_be_disabled->set__is_disabled( 1 );
} #disable_login

sub enable_account {
    my( $self, $account_to_be_enabled, $logged_in_account ) = @_;
    die "Access Error" unless $logged_in_account->get_login()->is_root();
    $account_to_be_enabled->set__is_disabled( 0 );
}  #enable_account

sub enable_login {
    my( $self, $login_to_be_enabled, $logged_in_account ) = @_;
    die "Access Error" unless $logged_in_account->get_login()->is_root();
    $login_to_be_enabled->set__is_disabled( 0 );
}  #enable_login

#
# Returns a list starting with the app object, followed by objects that the app wants to bring with
#
sub fetch_app_by_class {
    my( $self, $data ) = @_;
    my $app = $self->get__apps({})->{ $data };
    unless( $app ) {
        eval ("use $data");
        die $@ if $@;
        $app = $data->new();
        $app->set__key( $data );
        $self->get__apps()->{ $data } = $app;
    }
    return $app;
} #fetch_app_by_class


#
# Returns singleton Yote::Root object.
#
sub fetch_root {
    $Yote::Root::ROOT_INIT = 1;
    my $root = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    unless( $root ) {
        $root = new Yote::Root();
        Yote::ObjProvider::stow( $root );
    }
    $Yote::Root::ROOT_INIT = 0;
    return $root;
} #fetch_root

#
# Returns this root object.
#
sub fetch_initial {
    my( $self, $data, undef, $env ) = @_;
    my $app   = $data->{ a } ? $self->fetch_app_by_class( $data->{ a } ) : $self;
    my $login = $self->token_login( $data->{ t }, undef, $env );
    my $acct = $app && $login ? $app->__get_account( $login ) : undef;
    return { root	   => $self,
             app	   => $app,
             login	   => $login,
             account	   => $acct,
             guest_token   => $env->{GUEST_TOKEN},
             precache_data => $app ? $app->precache( '', $acct ) : undef,
	};
} #fetch_initial

#
# Clears out old data from guest and login token stores ( older than an hour )
#
sub clear_old_tokens {
    my( $self, $dummy, $acct ) = @_;
    die "Access Error" unless $acct && $acct->get_login() && $acct->get_login()->is_root();
    return $self->_clear_old_tokens();
} #clear_old_tokens

sub _clear_old_tokens {
    my( $self ) = @_;
    my $tok_store = $IP_TO_GUEST_TOKEN;
    my $registered_containers = $REGISTERED_CONTAINERS;
    my $time = time - 3600;
    my $count;
    for my $ip (keys %$tok_store) {
        my $hash = $tok_store->{ $ip };
        unless( ref $hash ) {
            delete $tok_store->{ $ip };
        } else {
            for my $tok ( keys %$hash ) {
                if( $hash->{ $tok } < $time ) {
                    ++$count;
                    delete $hash->{ $tok };
                    delete $registered_containers->{ $tok };
                    my $todel = $ALLOWS_REV->{ $tok };
                    if( $todel ) {
                        for my $obj_id (grep { $ALLOWS->{ $_ } } keys %$todel) {
                            delete $ALLOWS->{ $obj_id }{ $tok };
                            if( scalar( keys %{ $ALLOWS->{ $obj_id } } ) == 0 ) {
                                delete $ALLOWS->{ $obj_id };
                            }
                        }
                    }
                    delete $ALLOWS_REV->{ $tok };
                }
            }
            if( scalar( keys %$hash ) == 0 ) {
                delete $tok_store->{ $ip };
            }
        }
    }
    return $count;
} #_clear_old_tokens

#
# Returns a token for non-logging in use.
#
sub guest_token {
    my( $self, $ip ) = @_;
    my $token = 'gtok' . int( rand 9 x 10 );
    my $tok_store = $IP_TO_GUEST_TOKEN; #TODO - put this in init
    $tok_store->{$ip}{$token} = time(); # @TODO - make sure this and the LOGIN_OBJECTS cache is purged regularly. cron maybe?
    Yote::ObjManager::clear_login( undef, $token );

    return $token;
} #guest_token

sub reset_connections {
    my $self = shift;
    $ALLOWS = {};
    $ALLOWS_REV = {};
    $REGISTERED_CONTAINERS = {};
    $IP_TO_GUEST_TOKEN = {};
}

sub check_guest_token {
    my( $self, $ip, $token ) = @_;
    my $tok_store = $IP_TO_GUEST_TOKEN; #TODO - put this in init
    return $token if $tok_store->{$ip}{$token};
} #check_guest_token

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
        if( $login && ( $login->get__password() eq Yote::encrypt_pass( $data->{p}, $login->get_handle()) ) ) {
            die "Access Error" if $login->get__is_disabled();
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
        Yote::ObjManager::clear_login( $login );
        $login->set__token();
    }
} #logout

#
# Used to wipe and reset a whole app's data. Use with caution
# and can only be used by the superuser.
#
sub purge_app {
    my( $self, $app_or_name, $acct ) = @_;
    die "Access Error" unless $acct && $acct->get_login() && $acct->get_login()->is_root();

    my $apps = $self->get__apps();
    my $app;
    if( ref( $app_or_name ) ) {
        $app = $app_or_name;
        my $aname = $app->get__key();
        if( $aname ) {
            delete $apps->{ $aname };
        }
        else {
            for my $key (keys %$apps) {
                if( $app->_is( $apps->{ $key } ) ) {
                    delete $apps->{ $key };
                    last;
                }
            }
        }
    }
    else {
        $app = delete $apps->{ $app_or_name };
    }
    $self->add_to__purged_apps( $app );
    return "Purged " . (ref( $app_or_name ) ? ref( $app_or_name ) : $app_or_name );
} #purge_app

sub register_app {
    my( $self, $data, $acct ) = @_;
    die "Register app requires name and class fields" unless $data->{ name } && $data->{ class };
    eval( "require $data->{ class }" );
    die $@ if $@;
    my $name = $data->{ name };
    my $apps = $self->get__apps({});
    die "App '$name' already registered" if $apps->{ $name };
    my $app = $data->{ class }->new( { _key => $name } );
    die 'Register_app class must subclass Yote::AppRoot' unless $app->isa( 'Yote::AppRoot' );
    $apps->{ $name } = $app;
    return $app;
} #register_app

sub flush_purged_apps {
    my( $self, $data, $acct ) = @_;
    die "Access Error" unless $acct->is_root();
    $self->set__purged_apps( [] );
    return 1;
} #flush_purged_apps

#
# Removes a login. Need not only to be logged in, but present all credentials
#   (client side) use : remove_login({h:'handle',e:'email',p:'password'});
#             returns : "deleted account"
#
sub remove_login {
    my( $self, $args, $acct, $env ) = @_;

    die "invalid arguments" unless ref( $args ) eq 'HASH';
    my( $login, $password ) = @$args{'l','p'};

    die "Cannot remove root" if $login->is_root() || $login->is_master_root();

    if( $acct->is_root() || ( $login &&
                              $login->_is( $acct->get_login() ) &&
                              Yote::encrypt_pass($password, $login->get_handle()) eq $login->get__password() &&
                              ! $login->is_master_root() ) )
    {
        my $handle = $login->get_handle();
        my $email  = $login->get_email();
        delete $self->get__handles()->{ $handle };
        delete $self->get__emails()->{ $email };
        $self->add_to__removed_logins( $login );
        return "deleted account";
    }
    die "unable to remove login";

} #remove_login

#
# reset by a recovery link.
#
sub root_reset_password {
    my( $self, $args, $acct ) = @_;

    die "Access Error" unless $acct && $acct->get_login()->is_root();

    my $root = Yote::Root::fetch_root();
    my $newpass = $args->{p};
    my $login   = $args->{l};

    if( $login ) {
        $login->set__password( Yote::encrypt_pass( $newpass, $login->get_handle() ) );
    }
    return "Reset Password";

} #root_reset_password

#
# Mark user validated
#
sub root_validate {
    my( $self, $args, $acct ) = @_;

    die "Access Error" unless $acct && $acct->get_login()->is_root();

    my $root = Yote::Root::fetch_root();
    my $login   = $args->{l};

    if( $login ) {
        $login->set__is_validated( 1 );
        $login->set__validated_on( time() );
    }
    return "Validated Account";

} #root_validate


#
# Purges old accounts that were removed from the removed_logins list.
# also makes sure all handles and emails in those hashes actually point
# to a login.
#
sub purge_deleted_logins {
    my( $self, $args, $acct, $env ) = @_;

    die "Access Error" unless $acct && $acct->get_login()->is_root();
    
    $self->_purge_deleted_logins();

} #purge_deleted_logins

sub _purge_deleted_logins {
    my( $self ) = @_;
    
    my( @removed );
    for my $store ('_handles', '_emails' ) {
        my $count = $self->_count( { name => $store } );
        my $skip = 0;
        my( @gonners );
        do {
            my $hash = $self->_paginate( { name => $store, limit => 1000, skip => $skip, return_hash => 1 } );
            for my $val ( keys %$hash ) {
                push @gonners, $val unless ref( $hash->{ $val } );
            }	    
            $skip += 1000;
            $count -= 1000;
        } while( $count > 0 );

        for my $gonner (@gonners) {
            $self->_hash_delete( $store, $gonner );
        }
        push @removed, scalar( @gonners );
    } #store

    my $flushed = $self->_count(  { name => '_removed_logins' } );
    $self->set__removed_logins( [] );

    return "Flushed $flushed removed accounts. Removed $removed[0] invalid handles and $removed[1] invalid emails";
    
} #_purge_deleted_logins

#
# Removes root privs from a login. Does not remove the last root if there is one
#
sub remove_root {
    my( $self, $login, $acct ) = @_;
    die "Access Error" unless $acct->is_root();
    die "Cannot remove master root account" if $login->get__is_master_root();
    $login->set__is_root( 0 );
    $login->set_is_root( 0 );
    return;
} #remove_root

#
# Resets the cron, emptying it with the default items
#
sub reset_cron {
    my( $self, $data, $acct ) = @_;
    $self->set__crond( new Yote::Cron() );
} #reset_cron

# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

#
# Makes sure there is a root account with the given credentials.
#
sub _update_master_root {
    my( $self, $master_root_handle, $master_root_password_hashed ) = @_;

    my $lc_handle = lc( $master_root_handle );

    my $old_root = $self->get__master_root();
    if( $old_root ) {
        if( $old_root->get_handle() ne $master_root_handle ) {
            $self->_hash_delete( '_handles', lc( $old_root->get_handle() ) );
            $old_root->set_handle( $master_root_handle );
            $self->_hash_insert( '_handles', $lc_handle, $old_root );
        }
        if( $old_root->get__password() ne $master_root_password_hashed ) {
            $old_root->set__password( $master_root_password_hashed );
        }
        return $old_root;
    }

    my $root_login = new Yote::Login();
    $root_login->set_handle( $master_root_handle );
    $root_login->set__is_validated(1);

    $self->set__master_root( $root_login );

    $root_login->set__time_created( time() );

    $self->_hash_insert( '_handles', $lc_handle, $root_login );

    $root_login->set__is_root( 1 );
    $root_login->set__is_master_root( 1 );

    $root_login->set__password( $master_root_password_hashed );

    return $root_login;
} #_update_master_root

#
# Creates a login with credentials provided
#   (client side) use : create_login({h:'handle',e:'email',p:'password'});
#             returns : { l => login object, t => token }
#
sub _create_login {
    my( $self, $handle, $email, $password, $env ) = @_;
    if( $handle ) {
        my $lc_handle = lc( $handle );
        if( $self->_hash_has_key( '_handles', $lc_handle ) ) {
            die "handle already taken";
        }
        if( $email ) {
            if( $self->_hash_has_key( '_emails', $email ) ) {
                die "email already taken";
            }
            unless( Email::Valid->address( $email ) || $email =~ /\@localhost$/ ) {
                die "invalid email '$email' $Email::Valid::Details";
            }
        }
        unless( $password ) {
            die "password required";
        }

        my $new_login = new Yote::Login();

        $new_login->set__is_root( 0 );
        $new_login->set_is_root( 0 );
        $new_login->set_handle( $handle );
        $new_login->set_email( $email );
        my $ip = $env->{REMOTE_ADDR};
        $new_login->set__created_ip( $ip );

        $new_login->set__time_created( time() );

        $new_login->set__password( Yote::encrypt_pass($password, $new_login->get_handle()) );

        $self->_hash_insert( '_emails', $email, $new_login ) if $email;
        $self->_hash_insert( '_handles', $lc_handle, $new_login );

        return $new_login;
    } #if handle

    die "no handle given";

} #_create_login


#
# Create token and store with the account and return it.
#
sub _create_token {
    my( $self, $login, $ip ) = @_;
    my $token = int( rand 9 x 10 );
    $login->set__token( $token."x$ip" );
    return $login->{ID}.'-'.$token;
}

#
# This takes a login object and
# generates a login token, associates it with
# the login and then returns it.
#
sub _register_login_with_validation_token {
    my( $self, $login ) = @_;

    my $validations = $self->get__validations();
    my $rand_token = int( rand 9 x 10 );
    while( $validations->{ $rand_token } ) {
        $rand_token = int( rand 9 x 10 );
    }

    $validations->{ $rand_token } = $login;
    $login->set__validation_token( $rand_token );

    return $rand_token;

} #_register_login_with_validation_token

sub _validate {
    my( $self, $token ) = @_;
    my $validations = $self->get__validations();
    my $login = $validations->{ $token };
    if( $login ) {
        $login->set__is_validated( 1 );
        $login->set__validated_on( time() );
    }
    return $login;
}

1;

__END__

=head1 NAME

Yote::Root

=head1 DESCRIPTION

This is the first object and the root of the object graph. It stores user logins and stores the apps themselves.

=head1 PUBLIC API METHODS

=over 4

=item clear_old_tokens

=item cron

Returns the cron. Only a root login may call this.

=item disable_account( account_to_be_disabled, logged_in_account )

Marks the _is_disabled flag for the account to be disabled. Throws
access exception unless the logged_in_account is a root one.

=item disable_login( login_to_be_disabled, logged_in_account )

Marks the _is_disabled flag for the login to be disabled. Throws
access exception unless the logged_in_account is a root one.

=item enable_account( account_to_be_enabled, logged_in_account )

Removes the _is_disabled flag for the account to be enabled. Throws
access exception unless the logged_in_account is a root one.

=item enable_login( login_to_be_enabled, logged_in_account )

Removes the _is_disabled flag for the login to be enabled. Throws
access exception unless the logged_in_account is a root one.

=item fetch( id_list )

Returns the list of the objects to the client provided the client is authroized to receive them.

=item fetch_app_by_class( package_name )

Returns the app object singleton of the given package name.

=item fetch_initial( { a : appname, t : logintoken } )

Returns a hash with the following fields : root, app, login, account, guest_token and precache_data .

=item flush_purged_apps

Removes the backups of purged apps.

=item guest_token

Creates and returns a guest token, associating it with the calling IP address.

=item login( { h: handle, p : password } )

Attempts to log the account in with the given credentials. Returns a data structre with
the login token and the login object.

=item logout

Invalidates the tokens of the currently logged in user.

=item make_root

Takes a login as an argument and makes it root. Throws access error if the callee is not root.

=item new_obj( optional_data_hash )

Returns a new yote object, initialized with the optional has reference.

=item new_root_obj( optional_data_hash )

Returns a new root yote object, initialized with the optional has reference.

=item new_template()

Returns a new Yote::SimpleTemplate object and marks its creator.

=item new_user_obj( optional_data_hash )

Returns a new user yote object, initialized with the optional has reference.

=item init - takes a hash of args, passing them to a new Yote::SQLite object and starting it up.

=item purge_app

This method may only be invoked by a login with the root bit set. This clears out the app entirely.

=item purge_deleted_logins

=item register_app

Registers the app object with the app key. This means there can be generic apps.

=item remove_root( login )

Removes the root bit from the login.

=item reset_cron

Removes and rebuilds the cron.

=back

=head1 PRIVATE DATA FIELDS

=over 4

=item _apps

Hash of classname to app singleton.

=item _emails

Hash of email to login object.

=item _handles

Hash of handle to login object.

=item _crond

A singleton instance of the Cron.

=item _application_lib_directories

A list of directories that Yote will use to look for perl packages.

=item __ALLOWS

A hash of recipient ids to a hash of objects ids whos clients are allowed to access this object.

=item __ALLOWS_REV

A hash of object ids to a hash of recipient ibds whos clients are allowed to access this object.

=item __DIRTY

A hash of recipient ids to a hash of objects ids that need refreshing for that recipient.

=item _account_roots

This is a hash of login ID to account.

=back

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
