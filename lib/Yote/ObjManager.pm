package Yote::ObjManager;

use strict;
use warnings;

$Yote::ObjManager::ALLOWS = {}; # obj_id  --> ( login id || guest token ) --> time
$Yote::ObjManager::DIRTY  = {}; # ( login id || guest token ) --> obj_id --> 1

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
    if( $login ) {
	my $ret = $Yote::ObjManager::ALLOWS->{ $obj_id }{ $login->{ID} };
	unless( $ret ) { # transfer from guest to logged in token, if needed
	    $ret = $Yote::ObjManager::ALLOWS->{ $obj_id }{ $guest_token };
	    if( $ret ) {
		$Yote::ObjManager::ALLOWS->{ $obj_id }{ $login->{ID} } = 1;
		delete $Yote::ObjManager::ALLOWS->{ $obj_id }{ $guest_token };
	    }
	}
	return $ret;
    }

    return $Yote::ObjManager::ALLOWS->{ $obj_id }{ $guest_token };
    
} #allows_access

sub clear_login {
    my( $login, $guest_token ) = @_;
    if( $login ) {
	delete $Yote::ObjManager::DIRTY->{ $login->{ID} };
    }
    delete $Yote::ObjManager::DIRTY->{ $guest_token };
}

# return a list of object ids whos data should be sent to the caller.
sub fetch_dirty {
    my( $login, $guest_token ) = @_;
    my $ids = [];
    if( $login ) {
	push @$ids, keys %{ $Yote::ObjManager::DIRTY->{ $login->{ID} } };
	delete $Yote::ObjManager::DIRTY->{ $login->{ID} };
    }
    push @$ids, keys %{ $Yote::ObjManager::DIRTY->{ $guest_token } };
    delete $Yote::ObjManager::DIRTY->{ $guest_token };
    return $ids;
}

sub mark_dirty {
    my( $obj_id ) = @_;
    my $obj_hash = $Yote::ObjManager::ALLOWS->{ $obj_id };
    for my $recip_id ( keys %$obj_hash ) {
	$Yote::ObjManager::DIRTY->{ $recip_id }{ $obj_id } = 1;
    }
}

sub register_object {
    my( $obj_id, $recipient_id ) = @_;
    die unless $obj_id;
    return unless $recipient_id;
    $Yote::ObjManager::ALLOWS->{ $obj_id }{ $recipient_id } = 1;
} #register_object



1;

__END__

=head1 NAME

Yote::AccessControl

=head1 DESCRIPTION

This pays attention to which objects have been given to which users or guests. 
