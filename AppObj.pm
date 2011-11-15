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

    print STDERR Data::Dumper->Dump( ["APP OBJ GOT Process command",$cmd] );

    my $appstr = $cmd->{a};
    if( defined( $appstr ) ) {
        my $apps = $root->get_apps({});
        my $app = $apps->{$appstr};
        unless( $app ) {
            eval {
                $app = $appstr->new;
                $apps->{$appstr} = $app;
            };
            if( $@ ) {
                return { err => "Unable to load application '$appstr'" };
            }
        }
        my $command = $cmd->{c};
        if( $app->valid_token( $cmd->{t} ) || $command eq 'create_account' || $command eq 'login' ) {
            return $app->$command( $cmd->{d} );
        }
        return { err => "'$cmd->{c}' not found for app '$appstr'" };
    }

    return {};
} #process_command

sub valid_token {
    my( $root, $t ) = @_;
    if( $t =~ /(.+)\+(.+)/ ) {
        my( $uid, $token ) = ( $1, $2 );
	my $acct = GServ::ObjProvider::fetch( $uid );
	return $acct && $acct->get_token() eq $token;
    }
    return 0;
} #valid_token

sub create_account {
    my( $root, $args ) = @_;
    #
    # validate account args. Needs handle (,email at some point)
    #
    my( $handle, $email ) = ( $args->{handle}, $args->{email} );
    if( $handle ) {# && $args->{email} ) {
	if( GServ::ObjProvider::xpath("/handles/$handle") ) {
	    return { err => "handle already taken" };
	}
	if( $email ) {
	    if( GServ::ObjProvider::xpath("/emails/$email") ) {
		return { err => "email already taken" };
	    }
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
	$newacct->save();

	my $accts = $root->get_handles({});
	$accts->{ $handle } = $newacct;
	my $emails = $root->get_emails({});
	$emails->{ $email } = $newacct;

    } 
    return { err => "no handle given" };

} #create_account

sub login {
    
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
