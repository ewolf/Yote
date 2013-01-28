package Yote::ObjManager;

use strict;
use warnings;

$Yote::ObjManager::LOGIN_OBJS = {};
$Yote::ObjManager::GUEST_OBJS = {};

sub allows_access {
    my( $obj_id, $app, $login, $guest_token ) = @_;

    unless( $obj_id ) {
	return 1 if $app && $app->isa( 'Yote::AppRoot' );
    }

    return 1 if $obj_id == 1 || ( $app && $obj_id == $app->{ID} ) || ( $login && $obj_id == $login->{ID} );

    my $obj = Yote::ObjProvider::fetch( $obj_id );
    #print STDERR Data::Dumper->Dump(["OBJMAN",$obj_id,$obj, '-000000000--------------------']);
    return 1 if ref( $obj ) !~/^(HASH|ARRAY)$/ && $obj->isa( 'Yote::AppRoot' );

    if( $login ) {
	return $Yote::ObjManager::LOGIN_OBJS->{ $login->{ID} }{ $obj_id };
    }

    return $Yote::ObjManager::GUEST_OBJS->{ $guest_token }{ $obj_id };
    
} #allows_access

sub knows_dirty {
    my( $dirty_delta, $app, $login, $guest_token ) = @_;

    return [ grep { allows_access( $_, $app, $login, $guest_token ) } @$dirty_delta ];
} #knows_dirty

sub register_object {
    my( $obj_id, $login, $guest_token ) = @_;
    print STDERR Data::Dumper->Dump(["REGISTER <<$obj_id>>"]);
    die unless $obj_id;
    my $t = time();
    if( $login ) {
	$Yote::ObjManager::LOGIN_OBJS->{ $login->{ID} }{ $obj_id } = $t;
    } else {
	$Yote::ObjManager::GUEST_OBJS->{ $guest_token }{ $obj_id } = $t;
    }

} #register_object



1;

__END__

=head1 NAME

Yote::AccessControl

=head1 DESCRIPTION

This pays attention to which objects have been given to which users or guests. 
