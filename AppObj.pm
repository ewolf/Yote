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

    my $appstr = $cmd->{a};
    my $app = $appstr ? $root->get_apps({})->{$appstr} : $root;
#    print STDERR Data::Dumper->Dump( ["APP OBJ GOT Process command",$cmd,"for $appstr $app"] );
    unless( $app ) {
        my $apps = $root->get_apps({});
	eval {
	    $app = $appstr->new;
	    $apps->{$appstr} = $app;
	};
	if( $@ ) {
	    return { err => "Unable to load application '$appstr'" };
	}
    }
    
    my $command = $cmd->{c};
    #
    # this will not process private (beginning with _) commands, 
    # and will execute the command if its a login request, 
    # new account request or has a valid token.
    #
    my $acct = $app->valid_token( $cmd->{t} );

    if( index( $command, '_' ) != 0 && (  $acct || $command eq 'create_account' || $command eq 'login' ) ) {
	return $app->$command( $cmd->{d}, $acct );
    }
    return { err => "'$cmd->{c}' not found for app '$appstr'" };
} #process_command

sub valid_token {
    my( $root, $t ) = @_;
    if( $t =~ /(.+)\+(.+)/ ) {
        my( $uid, $token ) = ( $1, $2 );
	my $acct = GServ::ObjProvider::fetch( $uid );
	return $acct && $acct->get_token() eq $token ? $acct : undef;
    }
    return undef;
} #valid_token

sub create_account {
    my( $root, $args ) = @_;
    #
    # validate account args. Needs handle (,email at some point)
    #
    my( $handle, $email, $password ) = ( $args->{h}, $args->{e}, $args->{p} );

    if( $handle ) {# && $args->{email} ) {
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

	# save password plaintext for now. crypt later
	$newacct->set_password( $password );
	
	$newacct->save();

	my $accts = $root->get_handles({});
	$accts->{ $handle } = $newacct;
	my $emails = $root->get_emails({});
	$emails->{ $email } = $newacct;
	
	return { msg => "created account" };
    } #if handle
    return { err => "no handle given" };

} #create_account

sub login {
    my( $self, $data ) = @_;
    my $acct = GServ::ObjProvider::xpath("/handles/$data->{h}");
    if( $acct && $acct->get_password() eq $data->{p} ) {
	#
	# Create token and store with the account and return it.
	#
	my $token = int( rand 9 x 10 );
	$acct->set_token( $token );
	return { msg => "logged in", t => $token };
    }
    return { err => "incorrect login" };
} #login

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
