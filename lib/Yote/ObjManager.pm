package Yote::ObjManager;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';

no warnings 'uninitialized';

sub allows_access {
    my( $obj_id, $app, $login, $guest_token ) = @_;

    #
    # a user is allowed to see :
    #   * the yote root object
    #   * an app root object
    #   * their own login
    #   * anything registered to them
    #

    unless( $obj_id ) {
	return 1 if $app && $app->isa( 'Yote::AppRoot' );
    }

    return 1 if $obj_id eq Yote::ObjProvider::first_id() || ( $app && $obj_id eq $app->{ID} ) || ( $login && $obj_id eq $login->{ID} );

    my $obj = Yote::ObjProvider::fetch( $obj_id );
    return 1 unless $obj;
    return 1 if ref( $obj ) !~/^(HASH|ARRAY)$/ && $obj->isa( 'Yote::AppRoot' );

    my $root = Yote::YoteRoot::fetch_root();
    my $ALLOWS = $root->get___ALLOWS();
    if( $login ) {
	my $ret = $ALLOWS->{ $obj_id }{ $login->{ID} };
	unless( $ret ) { # transfer from guest to logged in token, if needed
	    $ret = $ALLOWS->{ $obj_id }{ $guest_token };
	    if( $ret ) {
		$ALLOWS->{ $obj_id }{ $login->{ID} } = 1;
		delete $ALLOWS->{ $obj_id }{ $guest_token };
	    }
	}
	return $ret;
    }

    return $ALLOWS->{ $obj_id }{ $guest_token };
    
} #allows_access

sub clear_login {
    my( $login, $guest_token ) = @_;

    my $root = Yote::YoteRoot::fetch_root();    
    my $DIRTY = $root->get___DIRTY();
    my $ALLOWS_REV = $root->get___ALLOWS_REV();
    if( $login ) {
	delete $DIRTY->{ $login->{ID} };
	delete $ALLOWS_REV->{ $login->{ID} };
    }
    delete $DIRTY->{ $guest_token };
    delete $ALLOWS_REV->{ $guest_token };
}

# return a list of object ids whos data should be sent to the caller.
sub fetch_dirty {
    my( $login, $guest_token ) = @_;
    my $ids = [];
    my $root = Yote::YoteRoot::fetch_root();
    my $DIRTY = $root->get___DIRTY();
    if( $login ) {
	push @$ids, keys %{ $DIRTY->{ $login->{ID} } };
	delete $DIRTY->{ $login->{ID} };
    }
    push @$ids, keys %{ $DIRTY->{ $guest_token } };
    delete $DIRTY->{ $guest_token };
    return $ids;
}

sub mark_dirty {
    my( $obj_id ) = @_;

    return if $Yote::YoteRoot::ROOT_INIT;
    my $root = Yote::YoteRoot::fetch_root();
    my $DIRTY = $root->get___DIRTY();
    my $ALLOWS = $root->get___ALLOWS();
    my $obj_hash = $ALLOWS->{ $obj_id };
    for my $recip_id ( keys %$obj_hash ) {
	#must be or, so that DIRTY doesn't become dirty and start an infinite loop
	$DIRTY->{ $recip_id }{ $obj_id } ||= 1;  
    }
}

sub register_object {
    my( $obj_id, $recipient_id ) = @_;
    die unless $obj_id;
    return unless $recipient_id;
    my $root = Yote::YoteRoot::fetch_root();
    my $ALLOWS = $root->get___ALLOWS();
    my $ALLOWS_REV = $root->get___ALLOWS_REV();
    $ALLOWS->{ $obj_id }{ $recipient_id } ||= 1;
    $ALLOWS_REV->{ $recipient_id }{ $obj_id } ||= 1;

} #register_object



1;

__END__

=head1 NAME

Yote::AccessControl

=head1 DESCRIPTION

This module is the gatekeeper that decides which objects may returned to clients from
their calls by paying attention to what the server explicitly pushed out to the client.

The ObjManager class is not publically visible to the client.

=head2 PUBLIC API METHODS

=over 4

=item allows_access( $object_id, $app_object, $login_object, $guest_token )

This returns true for the following cases : The login object has the root bit set, 
the login was passed the object id in question, the app is an AppRoot, or the user is 
not logged in but has a guest token that may have been given access to that object_id.

=item clear_login( $login, $guest_token )

This method removes all information the ObjManager has about the passed in login ( if any ) and guest token.

=item fetch_dirty( $login, $guest_token )

Returns a list of object ids that need to be refreshed for the client of the login or guest token

=item mark_dirty( $obj_id )

Notes the object is dirty and checks to see if the object is registered with any logins or guest tokens so it can inform them.

=item register_object( $obj_id, $recipient_id )

Registers the object id with the passed in login id or guest token.

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
