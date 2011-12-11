package GServ::AppObj;

use strict;

use GServ::Obj;

use base 'GServ::Obj';

#
# The AppObj is the root object. It forwards to the correct app root.
# The request object has the fields :
#   a - class name of app to load. Blank for root.
#   c - command which is a sub of the app
#   d - argument list
#   t - token for being logged in
#
# either c or i must be given
sub process_command {
    my( $root, $cmd ) = @_;
#    print STDERR Data::Dumper->Dump( ["PC",$root,$cmd] );

    my $appstr = $cmd->{a};
    my $app = $appstr ? $root->get_apps({})->{$appstr} : $root;
    unless( $app ) {
	eval( "use $appstr" );
        my $apps = $root->get_apps({});
        $app = $appstr->new;
        $apps->{$appstr} = $app;
        $app->save;
    }
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
    elsif( $command eq 'stow' ) {
	return _stow( $app, $cmd->{d}, $acct );
    }
    elsif( $command eq 'fetch' ) {
	return _fetch( $app, $cmd->{d}, $acct );
    }
    elsif( index( $command, '_' ) != 0 && $acct ) {
        return $app->$command( $cmd->{d}, $acct );
    }
    return { err => "'$cmd->{c}' not found for app '$appstr'" };
} #process_command

sub _valid_token {
    my( $t, $ip ) = @_;
    if( $t =~ /(.+)\+(.+)/ ) {
        my( $uid, $token ) = ( $1, $2 );
        my $acct = GServ::ObjProvider::fetch( $uid );
        return $acct && $acct->get_token() eq "${token}x$ip" ? $acct : undef;
    }
    return undef;
} #valid_token

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
        
        # todo
        # $newacct->set_time_created();

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
        return { msg => "created account", t => _create_token( $newacct, $ip ) };
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
#    print STDERR Data::Dumper->Dump( ["IN LOGIN"] );
    my( $data, $ip ) = @_;
    if( $data->{h} ) {
	my $root = GServ::ObjProvider::fetch_root;
	my $acct = GServ::ObjProvider::xpath("/handles/$data->{h}");
#	print STDERR Data::Dumper->Dump( ["Done Login",$data,$ip,$acct] );
	if( $acct && ($acct->get_password() eq $data->{p}) ) {
	    return { msg => "logged in", t => _create_token( $acct, $ip ) };
	}
    }
    return { err => "incorrect login" };
} #_login

#
# Returns if the fetch is allowed to proceed. Meant to override. Default is true. 
# Takes two args : object to be fetched and data of request.
#
sub fetch {
    my( $obj, $data ) = @_;
    return 1;
}


#
# Returns if the stow is allowed to proceed. Meant to override. Default is true.
# Takes two args : object to be stowed and data of request.
#
sub stow {
    my( $obj, $data ) = @_;
    return 1;
}


sub _fetch {
    my( $app, $data, $acct ) = @_;
    if( $data->{id} ) {
	my $obj = GServ::ObjProvider::fetch( $data->{id} );
	if( $obj && 
	    GServ::AppProvider::a_child_of_b( $obj, $app ) &&
	    $app->fetch( $obj, $data ) )
	{
	    return { r => GServ::ObjProvider::raw_data( $obj ) };
	    
	}
    }
    return { err => "Unable to fetch $data->{ID}" };
} #_fetch

sub _stow {
    my( $app, $data, $acct ) = @_;
    if( $data->{id} ) {
	my $obj = GServ::ObjProvider::fetch( $data->{id} );
	if( $obj && 
	    GServ::AppProvider::a_child_of_b( $obj, $app ) &&
	    $app->stow( $obj, $data ) )
	{
	    #verify all incoming objects are also stowable
	    my $check = ref( $data->{v} ) eq 'ARRAY' ? @{$data->{v}}: [map { $data->{v}{$_} } grep { $_ ne '__KEY__' } %{$data->{v}}];	   
	    for my $item (grep { $_ > 0 } @$check) { #check all ids
		my $child = GServ::ObjProvider::fetch( $item );
		unless( $child &&
			GServ::AppProvider::a_child_of_b( $child, $app ) &&
			$app->stow( $child, $data ) )
		{
		    return { err => "Unable to update $data->{ID}" };
		}
	    }

	    #adjust the target object
	    if( ref( $obj ) eq 'ARRAY' ) {
		if( ref( $data->{v} ) eq 'ARRAY' ) {		    
		    my $tied = tied @$obj;
		    splice( @$tied, 1, $#$tied, @{$data->{v}} );
		} else {
		    return { err => "Missing data to update $data->{ID}" };
		}
	    }
	    elsif( ref( $obj ) eq 'HASH' ) {		
		if( ref( $data->{v} ) eq 'HASH' ) {
		    my $tied = tied %$obj;
		    for my $k (%{$data->{v}}) {
			$tied->{$k} = $data->{v}{$k};
		    }
		    for my $k (%$tied) {
			next if $k eq '__ID__';
			unless( defined( $data->{v}{$k} ) ) {
			    delete $tied->{$k};
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
	    return { r => GServ::ObjProvider::raw_data( $obj ), msg => 'updated' };
	}
    }
    return { err => "Unable to update $data->{ID}" };
} #_stow

1;

__END__

=head1 NAME

GServ::AppObj - Application Server Base Objects

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
