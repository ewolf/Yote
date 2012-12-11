package Yote::ObjManager;

use strict;

$Yote::ObjManager::LOGIN_OBJS = {};
$Yote::ObjManager::GUEST_OBJS = {};

sub allows_access {
    my( $obj_id, $app, $login, $guest_token ) = @_;

    unless( $obj_id ) {
	return $app->isa( 'Yote::AppRoot' );
    }

    return 1 if $obj_id == 1;


    if( $login ) {
	return $Yote::ObjManager::LOGIN_OBJS->{ $login->{ID} };
    }

    return $Yote::ObjManager::GUEST_OBJS->{ $guest_token };
    
} #allows_access

sub knows_dirty {
    my( $dirty_delta, $login, $guest_token ) = @_;

    if( $login ) {
	return [ grep { $Yote::ObjManager::LOGIN_OBJS->{ $login->{ID} }{ $_ } } @$dirty_delta ];
    }
    return [ grep { $Yote::ObjManager::GUEST_OBJS->{ $guest_token }{ $_ } } @$dirty_delta ];
} #knows_dirty

sub register_object {
    my( $obj_id, $login, $guest_token ) = @_;

    my $t = time();
    if( $login ) {
	$Yote::ObjManager::LOGIN_OBJS->{ $login->{ID} }{ $_ } = $t;
    } else {
	$Yote::ObjManager::GUEST_OBJS->{ $guest_token }{ $_ } = $t;
    }

} #register_object



1;

__END__

=head1 NAME

Yote::AccessControl

=head1 DESCRIPTION

This pays attention to which objects have been given to which users or guests. 
