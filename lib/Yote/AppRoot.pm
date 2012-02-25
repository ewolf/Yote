package Yote::AppRoot;

use strict;

use Yote::Obj;

use Crypt::Passwd;
use Email::Valid;
use MIME::Lite;
use MIME::Base64;

use vars qw($VERSION);

$VERSION = '0.01';

use base 'Yote::Obj';

#
# Returns the account root attached to this AppRoot for the given account.
#
sub _get_account_root {
    my( $self, $acct ) = @_;

    my $acct_roots = $self->get_account_roots({});
    my $root = $acct_roots->{$acct->{ID}};
    unless( $root ) {
        $root = new Yote::Obj;
        $acct_roots->{$acct->{ID}} = $root;
    }
    return $root;

} #_get_account_root

#
# Process_command is only called on the master root, 
#   which will route the command to the appropriate root.
#
# The AppRoot is the root object. It forwards to the correct app root.
# The request object has the fields :
#
#   id - id of object to run method against
#   a - app that the object is for.
#   c - command or method to run
#   d - argument data
#   t - token for being logged in
#
# either c or i must be given
sub _process_command {
    my( $root, $cmd ) = @_;

    my $command = $cmd->{c};

    my $data = _translate_data( $cmd->{d} );

    #
    # this will not process private (beginning with _) commands,
    # and will execute the command if its a login request,
    # new account request or has a valid token.
    #
    my $acct = _valid_token( $cmd->{t}, $cmd->{oi} );
    if( $command eq 'create_account' ) {
        return $root->_create_account( $data, $cmd->{oi} );
    }
    elsif( $command eq 'login' ) {
        return _login( $data, $cmd->{oi} );
    }
    elsif( $command eq 'remove_account' ) {
        return $root->_remove_account( $data, $acct );
    }
    elsif( $command eq 'recover_password' ) {
        return $root->_recover_password( $data );
    }
    elsif( $command eq 'reset_password' ) {
        return $root->_reset_password( $data );
    }
    else {
        my $appstr = $command eq 'fetch_root' && ref($data) ? $data->{app} : $cmd->{a};
        my $app;
        if( $appstr ) {
            
            $app = $root->get_apps({})->{$appstr};

            #generate the app if not present.
            unless( $app ) {
                eval( "use $appstr" );
                if( $@ =~ /Can.t locate/ ) {
                    return { err => "App '$a' not found" };
                }
                my $apps = $root->get_apps();
                $app = $appstr->new;
                $apps->{$appstr} = $app;
                $app->save;
            } 
        }
        else {
            $app = $root;
        }            

        if( $command eq 'fetch_root' ) {
            return _fetch( $app, { id => $app->{ID} }, $acct );
        }
        elsif( $command eq 'fetch' ) {
            return _fetch( $app, { id => $data->{id} }, $acct );
        }
        elsif( $command eq 'multi_fetch' ) {
            return _multi_fetch( $app, { ids => $data->{ids} }, $acct );
        }
        elsif( $command eq 'update' ) {
            my $obj = Yote::ObjProvider::fetch( $data->{id} );
            if( $obj && $app->_stow_permitted( $data->{d} ) ) {
                $obj->absorb( $data->{d} );
                return { msg => "updated" };
            }
            return { err => "unable to update" };
        }

        my $obj = Yote::ObjProvider::fetch( $cmd->{id} ) || $app;
        if( $app->_allows( $command, $data, $acct ) && $obj->can( $command ) ) {
            my %before = map { $_ => 1 } (Yote::ObjProvider::dirty_ids());
            my $resp = $app->_obj_to_response( $obj->$command( $data,
                                                               $app->_get_account_root( $acct ),
                                                               $acct ), 1 );
            my @dirty_delta = grep { ! $before{$_} } (Yote::ObjProvider::dirty_ids());
            return { r => $resp, d => \@dirty_delta };
        } 
        return { err => "'$cmd->{c}' not found for app '$appstr'" };
    }
} #_process_command

# this makes the account root visible to javascript, which will have easier access to its methods.
sub fetch_account_root {
    my( $self, $data, $acct_root, $acct ) = @_;
    return  { r => $acct_root };
}

sub _translate_data {
    my $val = shift;

    if( ref( $val ) ) { #from javacript object, or hash
        return { map {  $_ => _translate_data( $val->{$_} ) } keys %$val };
    }
    return undef unless $val;
    return index($val,'v') == 0 ? substr( $val, 1 ) : Yote::ObjProvider::fetch( $val );
}

#
# Override to control access to this app.
#
sub _allows { 
    my( $app, $command, $data, $acct ) = @_;
    return 0 if index( $command, '_' ) == 0 || $command eq 'absorb';
    return 1;
}

#
# Fetch master root singleton object.
#
sub fetch_root {
    my $root = Yote::ObjProvider::fetch( 1 );
    unless( $root ) {
        $root = new Yote::AppRoot();
        $root->save;
    }
    return $root;
}

sub _valid_token {
    my( $t, $ip ) = @_;
    if( $t =~ /(.+)\+(.+)/ ) {
        my( $uid, $token ) = ( $1, $2 );
        my $acct = Yote::ObjProvider::fetch( $uid );
        return $acct && $acct->get_token() eq "${token}x$ip" ? $acct : undef;
    }
    return undef;
} #valid_token

sub _recover_password {
    my( $root, $args ) = @_;
    my $email = $args->{e};
    my $from_url = $args->{u};
    my $to_reset = $args->{t};
    my $acct = $root->get_emails({})->{$email};
    if( $acct ) {
        my $now = time();
        if( $now - $acct->get_last_recovery_time() > (60*15) ) { #need to wait 15 mins
            my $rand_token = int( rand 9 x 10 );
            my $recovery_hash = $root->get_recovery_accts({});
            my $times = 0;
            while( $recovery_hash->{$rand_token} && ++$times < 100 ) {
                $rand_token = int( rand 9 x 10 );
            }
            if( $recovery_hash->{$rand_token} ) {
                return { err => "error recovering password" };
            }
            $acct->set_recovery_token( $rand_token );
            $acct->set_recovery_from_url( $from_url );
            $acct->set_last_recovery_time( $now );
            $acct->set_recovery_tries( $acct->get_recovery_tries() + 1 );
            $recovery_hash->{$rand_token} = $acct;
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
            return { err => "password recovery attempt failed" };
        }
    }
    return { r => "password recovery initiated" };
} #_recover_password

sub _reset_password {
    my( $root, $args ) = @_;

    my $rand_token = $args->{t};
    my $newpass = $args->{p};

    my $recovery_hash = $root->get_recovery_accts({});
    my $acct = $recovery_hash->{$rand_token};
    if( $acct ) {
        my $now = $acct->get_last_recovery_time();
        delete $recovery_hash->{$rand_token};
        if( ( time() - $now ) < 3600 * 24 ) { #expires after a day
            $acct->set_password( _encrypt_pass( $newpass, $acct ) );
            $acct->set_recovery_token( undef );
            return { r => "Password Reset" };
        }
    }
    return { err => "Recovery Link Expired or not valid" };
} #_reset_password

sub _remove_account {
    my( $root, $args, $acct ) = @_;
    if( $acct && _encrypt_pass($args->{p}, $acct) eq $acct->get_password() && $args->{h} eq $acct->get_handle() && $args->{e} eq $acct->get_email() ) {
        delete $root->get_handles()->{$args->{h}};
        delete $root->get_emails()->{$args->{e}};
        return { r => "deleted account" };
    } 
    return { err => "unable to remove account" };
} #_remove_account

sub _create_account {
    my( $root, $args, $ip ) = @_;

    #
    # validate account args. Needs handle (,email at some point)
    #
    my( $handle, $email, $password ) = ( $args->{h}, $args->{e}, $args->{p} );
    if( $handle ) {# && $email ) {
        if( Yote::ObjProvider::xpath("/handles/$handle") ) {
            return { err => "handle already taken" };
        }
        if( $email ) {
            if( Yote::ObjProvider::xpath("/emails/$email") ) {
                return { err => "email already taken" };
            }
            unless( Email::Valid->address( $email ) ) {
                return { err => "invalid email" };
            }
        }
        unless( $password ) {
            return { err => "password required" };
        }
        my $newacct = new Yote::Obj();

        #
        # check to see how many accounts there are. If there are none,
        # give the first root access.
        #
        if( Yote::ObjProvider::xpath_count( "/handles" ) == 0 ) {
            $newacct->set_is_root( 1 );
        }
        $newacct->set_handle( $handle );
        $newacct->set_email( $email );
        $newacct->set_created_ip( $ip );

        $newacct->set_time_created( time() );

        # save password plaintext for now. crypt later
        $newacct->set_password( _encrypt_pass($password, $newacct) );

        $newacct->save();

        my $accts = $root->get_handles({});
        $accts->{ $handle } = $newacct;
        Yote::ObjProvider::stow( $accts );
        my $emails = $root->get_emails({});
        $emails->{ $email } = $newacct;
        Yote::ObjProvider::stow( $emails );
        $root->save;
        return { r => "created account", a => $root->_obj_to_response( $newacct ), t => _create_token( $newacct, $ip ) };
    } #if handle
    return { err => "no handle given" };

} #_create_account


#
# Create token and store with the account and return it.
#
sub _create_token {
    my( $acct, $ip ) = @_;
    my $token = int( rand 9 x 10 );
    $acct->set_token( $token."x$ip" );
    return $acct->{ID}.'+'.$token;
}

sub _login {
    my( $data, $ip ) = @_;
    if( $data->{h} ) {
        my $root = fetch_root();
        my $acct = Yote::ObjProvider::xpath("/handles/$data->{h}");
        if( $acct && ($acct->get_password() eq _encrypt_pass( $data->{p}, $acct) ) ) {
            return { r => "logged in", a => $root->_obj_to_response( $acct ), t => _create_token( $acct, $ip ) };
        }
    }
    return { err => "incorrect login" };
} #_login

sub _encrypt_pass {
    my( $pw, $acct ) = @_;
    return $acct ? unix_std_crypt( $pw, $acct->get_handle() ) : undef;
} #_encrypt_pass

#
# Returns if the fetch is allowed to proceed. Meant to override. Default is true.
# Takes two args : object to be fetched and data of request.
#
sub _fetch_permitted {
    my( $obj, $data ) = @_;
    return 1;
}


#
# Returns if the stow is allowed to proceed. Meant to override. Default is true.
# Takes two args : object to be stowed and data of request.
#
sub _stow_permitted {
    my( $obj, $data ) = @_;
    return 1;
}

#
# Returns a data structure with the following fields :
#   m - names of methods
#   d - key value data, where value can be a referece (is a number) or a scalar (is prepended with 'v' )
#
sub _fetch {
    my( $app, $data, $acct ) = @_;
    if( $data->{id} ) {
        my $obj = Yote::ObjProvider::fetch( $data->{id} );
        if( $obj &&
            Yote::ObjProvider::a_child_of_b( $obj, $app ) &&
            $app->_fetch_permitted( $obj, $data ) )
        {
            return { r => $app->_obj_to_response( $obj ) };
        }
    }
    return { err => "Unable to fetch $data->{id}" };
} #_fetch


#
# Returns a list of data structure with the following fields :
#   m - names of methods
#   d - key value data, where value can be a referece (is a number) or a scalar (is prepended with 'v' )
#
sub _multi_fetch {
    my( $app, $data, $acct ) = @_;
    if( $data->{ids} ) {
        my %ret;
        for my $id (values %{$data->{ids}}) {
            my $obj = Yote::ObjProvider::fetch( $id );
            if( $obj &&
                Yote::ObjProvider::a_child_of_b( $obj, $app ) &&
                $app->_fetch_permitted( $obj, $data ) )
            {
                $ret{$id} = $app->_obj_to_response( $obj );
            }
        }
        return { r => \%ret };
    } #if ids given
    return { err => "Unable to fetch $data->{ids}" };
} #_multi_fetch

#
# Transforms data structure but does not assign ids to non tied references.
#
sub _transform_data_no_id {
    my( $self, $item ) = @_;
    if( ref( $item ) eq 'ARRAY' ) {
        my $tied = tied @$item;
        if( $tied ) {
            return Yote::ObjProvider::get_id( $item ); 
        }
        return [map { $self->_obj_to_response( $_, 1 ) } @$item];
    }
    elsif( ref( $item ) eq 'HASH' ) {
        my $tied = tied %$item;
        if( $tied ) {
            return Yote::ObjProvider::get_id( $item ); 
        }
        return { map { $_ => $self->_obj_to_response( $item->{$_}, 1 ) } keys %$item };
    }
    elsif( ref( $item ) ) {
        return  Yote::ObjProvider::get_id( $item ); 
    }
    else {
        return "v$item"; #scalar case
    }
} #_transform_data_no_id

#
# Converts scalar, yote object, hash or array to data for returning.
#
sub _obj_to_response {
    my( $self, $to_convert, $xform_out ) = @_;
    my $ref = ref($to_convert);
    my $use_id;
    if( $ref ) {
        my( $m, $d ) = ([]);
        if( ref( $to_convert ) eq 'ARRAY' ) {
            my $tied = tied @$to_convert;
            if( $tied ) {
                $d = $tied->[1];
                $use_id = Yote::ObjProvider::get_id( $to_convert );
                return $use_id if $xform_out;
            } else {
                $d = $self->_transform_data_no_id( $to_convert );
            }
        } 
        elsif( ref( $to_convert ) eq 'HASH' ) {
            my $tied = tied %$to_convert;
            if( $tied ) {
                $d = $tied->[1];
                $use_id = Yote::ObjProvider::get_id( $to_convert );
                return $use_id if $xform_out;
            } else {
                $d = $self->_transform_data_no_id( $to_convert );
            }
        } 
        else {
            $use_id = Yote::ObjProvider::get_id( $to_convert );
            return $use_id if $xform_out;
            $d = $to_convert->{DATA};
            no strict 'refs';
            $m = [ grep { $_ !~ /^(_.*|[A-Z].*|set_.*|is|clone|can|fetch_root|import|init|isa|new|save|absorb)$/ } keys %{"${ref}\::"} ];
            use strict 'refs';
        }
        return { a => ref( $self ), c => $ref, id => $use_id, d => $d, 'm' => $m };
    } # if a reference
    return "v$to_convert" if $xform_out;
    return $to_convert;
} #_obj_to_response

sub _stow {
    my( $app, $data, $acct ) = @_;
    if( $data->{id} ) {
        my $obj = Yote::ObjProvider::fetch( $data->{id} );
        if( $obj &&
            Yote::ObjProvider::a_child_of_b( $obj, $app ) &&
            $app->stow( $obj, $data ) )
        {
            #verify all incoming objects are also stowable
            my $check = ref( $data->{v} ) eq 'ARRAY' ? @{$data->{v}}: [map { $data->{v}{$_} } grep { $_ ne '__KEY__' } %{$data->{v}}];
            for my $item (grep { $_ > 0 } @$check) { #check all ids
                my $child = Yote::ObjProvider::fetch( $item );
                unless( $child &&
                        Yote::ObjProvider::a_child_of_b( $child, $app ) &&
                        $app->stow( $child, $data ) )
                {
                    return { err => "Unable to update $data->{ID}" };
                }
            }

            #adjust the target object
            if( ref( $obj ) eq 'ARRAY' ) {
                if( ref( $data->{v} ) eq 'ARRAY' ) {
                    my $tied = tied @$obj;
                    splice @{$tied->[1]}, 0, scalar(@{$tied->[1]}), @{$data->{v}};
                } else {
                    return { err => "Missing data to update $data->{ID}" };
                }
            }
            elsif( ref( $obj ) eq 'HASH' ) {
                if( ref( $data->{v} ) eq 'HASH' ) {
                    my $tied = tied %$obj;
                    for my $k (%{$data->{v}}) {
                        $tied->[1]{$k} = $data->{v}{$k};
                    }
                    for my $k (%{$tied->[1]}) {
                        unless( defined( $data->{v}{$k} ) ) {
                            delete $tied->[1]{$k};
                        }
                    }
                } else {
                    return { err => "Missing data to update $data->{ID}" };
                }
            }
            else { #object
                if( ref( $data->{v} ) eq 'HASH' ) {
                    for my $k (%{$data->{v}}) {
                        $obj->{DATA}{$k} = $data->{v}{$k};
                    }
                    for my $k (%{$obj->{DATA}}) {
                        unless( defined( $data->{v}{$k} ) ) {
                            delete $obj->{DATA}{$k};
                        }
                    }
                } else {
                    return { err => "Missing data to update $data->{ID}" };
                }
            }
            Yote::ObjProvider::stow( $obj );
            return { r => 'updated' };
        }
    }
    return { err => "Unable to update $data->{ID}" };
} #_stow

1;

__END__

=head1 NAME

Yote::AppRoot - Application Server Base Objects

=head1 SYNOPSIS

This object is meant to be extended to provide Yote apps.

=head1 DESCRIPTION

Each Web Application has a single container object as the entry point to that object which is an instance of the Yote::AppRoot class. A Yote::AppRoot extends Yote::Obj and provides some class methods and the following stub methods.

=head2 CLASS METHODS

=over 4

=item fetch_root - returns the master root object.

The master root object contains all web application roots. It is an AppRoot object.

Returns the root object. This is always object 1 for the App Server.

=back

=head2 STUB METHODS

=over 4

=item init - called the first time this root is created. Initializes account root.

=back

=head3 INSTANCE METHODS

=over 4

=item _get_account_root( login ) - Returns an account object associated with a login object.

=back

The account root is there to store information specific to the account in question. It could include 
documents specific to the account or games the account is participating in. This is distinct from the
login object itself, though there is a one to one mapping between the account root and the login.

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
