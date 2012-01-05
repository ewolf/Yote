package GServ::AppRoot;

use strict;

use GServ::Obj;

use base 'GServ::Obj';

sub init {
    my $self = shift;
    # account root is used to hold account specific data for this app.
    $self->set_account_root( new GServ::Obj );
} #init

#
# Returns the account root attached to this AppRoot for the given account.
#
sub get_account_root {
    my( $self, $acct ) = @_;

    my $acct_roots = $self->get_account_roots({});
    my $root = $acct_roots->{$acct->{ID}};
    unless( $root ) {
        $root = new GServ::Obj;
    }
    return $root;

} #get_account_root

#
# Process_command is only called on the master root, which will route the command to the appropriate root.
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
sub process_command {
    my( $root, $cmd ) = @_;

    my $command = $cmd->{c};

    #
    # this will not process private (beginning with _) commands,
    # and will execute the command if its a login request,
    # new account request or has a valid token.
    #
    my $acct = _valid_token( $cmd->{t}, $cmd->{oi} );
    if( $command eq 'create_account' ) {
        return $root->_create_account( $cmd->{d}, $cmd->{oi} );
    }
    elsif( $command eq 'login' ) {
        return _login( $cmd->{d}, $cmd->{oi} );
    }
    elsif( $command eq 'remove_account' ) {
	return $root->_remove_account( $cmd->{d}, $acct );
    }
    else {
        my $appstr = $command eq 'fetch_root' && ref($cmd->{d}) ? $cmd->{d}->{app} : $cmd->{a};
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
            return _fetch( $app, { id => $cmd->{d}{id} }, $acct );
        }
        elsif( index( $command, '_' ) != 0 ) {
            my $obj = GServ::ObjProvider::fetch( $cmd->{id} ) || $app;
            if( $app->allows( $cmd->{d}, $acct ) && $obj->can( $command ) ) {
		return { r => $app->_obj_to_response( $app->$command( $cmd->{d}, $acct ) ) };
	    }
            return { err => "'$cmd->{c}' not found for app '$appstr'" };
        }
        return { err => "'$cmd->{c}' not found for app '$appstr'" };
    }
} #process_command

#
# Override to control access to this app.
#
sub allows { 
    my( $app, $data, $acct ) = @_;
    return 1;
}

sub fetch_root {
    my $root = GServ::ObjProvider::fetch( 1 );
    unless( $root ) {
        $root = new GServ::AppRoot();
        $root->save;
    }
    return $root;
}

sub _valid_token {
    my( $t, $ip ) = @_;
    if( $t =~ /(.+)\+(.+)/ ) {
        my( $uid, $token ) = ( $1, $2 );
        my $acct = GServ::ObjProvider::fetch( $uid );
        return $acct && $acct->get_token() eq "${token}x$ip" ? $acct : undef;
    }
    return undef;
} #valid_token

sub _remove_account {
    my( $root, $args, $acct ) = @_;
    if( $acct && $args->{p} eq $acct->get_password() && $args->{h} eq $acct->get_handle() && $args->{e} eq $acct->get_email() ) {
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
        if( GServ::ObjProvider::xpath("/handles/$handle") ) {
            return { err => "handle already taken" };
        }
        if( $email ) {
            if( GServ::ObjProvider::xpath("/emails/$email") ) {
                return { err => "email already taken" };
            }
        }
        unless( $password ) {
            return { err => "password required" };
        }
        my $newacct = new GServ::Obj();

        #
        # check to see how many accounts there are. If there are none,
        # give the first root access.
        #
        if( GServ::ObjProvider::xpath_count( "/handles" ) == 0 ) {
            $newacct->set_is_root( 1 );
        }
        $newacct->set_handle( $handle );
        $newacct->set_email( $email );
        $newacct->set_created_ip( $ip );

	$newacct->set_time_created( time() );

        # save password plaintext for now. crypt later
        $newacct->set_password( $password );

        $newacct->save();

        my $accts = $root->get_handles({});
        $accts->{ $handle } = $newacct;
        GServ::ObjProvider::stow( $accts );
        my $emails = $root->get_emails({});
        $emails->{ $email } = $newacct;
        GServ::ObjProvider::stow( $emails );
        $root->save;
        return { r => "created account", t => _create_token( $newacct, $ip ) };
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
        my $acct = GServ::ObjProvider::xpath("/handles/$data->{h}");
        if( $acct && ($acct->get_password() eq $data->{p}) ) {
            return { r => "logged in", t => _create_token( $acct, $ip ) };
        }
    }
    return { err => "incorrect login" };
} #_login

#
# Returns if the fetch is allowed to proceed. Meant to override. Default is true.
# Takes two args : object to be fetched and data of request.
#
sub fetch_permitted {
    my( $obj, $data ) = @_;
    return 1;
}


#
# Returns if the stow is allowed to proceed. Meant to override. Default is true.
# Takes two args : object to be stowed and data of request.
#
sub stow_permitted {
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
        my $obj = GServ::ObjProvider::fetch( $data->{id} );
        if( $obj &&
            GServ::ObjProvider::a_child_of_b( $obj, $app ) &&
            $app->fetch_permitted( $obj, $data ) )
        {
	    return { r => $app->_obj_to_response( $obj ) };
        }
    }
    return { err => "Unable to fetch $data->{ID}" };
} #_fetch

#
# Trasnforms data structure but does not assign ids to non tied references.
#
sub _transform_data_no_id {
    my $item = shift;
    if( ref( $item ) eq 'ARRAY' ) {
	my $tied = tied @$item;
	if( $tied ) {
	    return GServ::ObjProvider::get_id( $item ); 
	}
	return [map { _transform_data_no_id( $_ ) } @$item];
    }
    elsif( ref( $item ) eq 'HASH' ) {
	my $tied = tied %$item;
	if( $tied ) {
	    return GServ::ObjProvider::get_id( $item ); 
	}
	return { map { $_ => _transform_data_no_id( $item->{$_} ) } keys %$item};
    }
    elsif( ref( $item ) ) {
	return  GServ::ObjProvider::get_id( $item ); 
    }
    else {
	return "v$item"; #scalar case
    }
} #_transform_data_no_id

#
# Converts scalar, gserv object, hash or array to data for returning.
#
sub _obj_to_response {
    my( $self, $to_convert ) = @_;
    my $ref = ref($to_convert);
    my $use_id;
    if( $ref ) {
	my( $m, $d ) = ([]);
	if( ref( $to_convert ) eq 'ARRAY' ) {
	    my $tied = tied @$to_convert;
	    if( $tied ) {
		$d = $tied->[1];
		$use_id = GServ::ObjProvider::get_id( $to_convert );
	    } else {
		$d = _transform_data_no_id( $to_convert );
	    }
	} 
	elsif( ref( $to_convert ) eq 'HASH' ) {
	    my $tied = tied %$to_convert;
	    if( $tied ) {
		$d = $tied->[1];
		$use_id = GServ::ObjProvider::get_id( $to_convert );
	    } else {
		$d = _transform_data_no_id( $to_convert );
	    }
	} 
	else {
	    $use_id = GServ::ObjProvider::get_id( $to_convert );
	    $d = $to_convert->{DATA};
	    no strict 'refs';
	    $m = [ grep { $_ !~ /^([_A-Z].*|allows|can|fetch_root|fetch_permitted|[i]mport|init|isa|new|save)$/ } keys %{"${ref}\::"} ];
	    use strict 'refs';
	}
	return { a => ref( $self ), c => $ref, id => $use_id, d => $d, 'm' => $m };
    } # if a reference
    return $to_convert;
} #_obj_to_response

sub _stow {
    my( $app, $data, $acct ) = @_;
    if( $data->{id} ) {
        my $obj = GServ::ObjProvider::fetch( $data->{id} );
        if( $obj &&
            GServ::ObjProvider::a_child_of_b( $obj, $app ) &&
            $app->stow( $obj, $data ) )
        {
            #verify all incoming objects are also stowable
            my $check = ref( $data->{v} ) eq 'ARRAY' ? @{$data->{v}}: [map { $data->{v}{$_} } grep { $_ ne '__KEY__' } %{$data->{v}}];
            for my $item (grep { $_ > 0 } @$check) { #check all ids
                my $child = GServ::ObjProvider::fetch( $item );
                unless( $child &&
                        GServ::ObjProvider::a_child_of_b( $child, $app ) &&
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
            GServ::ObjProvider::stow( $obj );
            return { r => 'updated' };
        }
    }
    return { err => "Unable to update $data->{ID}" };
} #_stow

1;

__END__

=head1 NAME

GServ::AppRoot - Application Server Base Objects

=head1 SYNOPSIS

    This object is meant to be extended to provide GServ apps.

=head1 DESCRIPTION



=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
