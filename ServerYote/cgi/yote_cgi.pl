#!/usr/bin/perl

use strict;
use warnings;
no warnings 'uninitialized';

use Yote;

use CGI;
use DateTime;
use Data::Dumper;
use JSON;

my $cgi = CGI->new;

my $json_payload = $cgi->param('p');

my $payload = from_json( $json_payload );

my( $obj_id, $token, $action, $params ) = @$payload{ 'i', 't', 'a', 'pl' };

unless( $main::yote_server ) {
    eval('use Yote::ConfigData');
    my $yote_root_dir = $@ ? '/opt/yote' : Yote::ConfigData->config( 'yote_root' );

    my $options = Yote::Server::load_options( $yote_root_dir );

    $main::yote_server = new Yote::Server( $options );
}

my $store = $main::yote_server->store;
my $server_root = $store->fetch_server_root;
my $server_root_id = $server_root->{ID};

my $session = $server_root->_fetch_session( $token );

unless( $obj_id eq '_' || 
        $obj_id eq $server_root_id || 
        substr($action,0,1) eq '_' ||
        ( $obj_id > 0 && 
          $session && 
          $server_root->_getMay( $obj_id, $session->get__token ) ) ) {

    # CGI not sock
    print $cgi->header( -status => '400 BAD REQUEST' );
    return '';
}

my $obj = $obj_id eq '_' ? $server_root :
    $store->fetch( $obj_id );

unless( $obj->can( $action ) ) {
    _log( "Bad Req : invalid method :'$action'" );
    print $cgi->header( -status => '400 BAD REQUEST' );
    return;
}


my( @res );
eval {
    my $in_params = $self->__transform_params( $params, $token, $server_root );

    if( $session ) {
        $obj->{SESSION} = $session;
        $obj->{SESSION}{SERVER_ROOT} = $server_root;
    }
    (@res) = ($obj->$action( @$in_params ));
};
delete $obj->{SESSION};

if ( $@ ) {
    _log( "INTERNAL SERVER ERROR '$@'", 0 );
    $sock->print( "HTTP/1.1 500 INTERNAL SERVER ERROR\n\n" );
    $sock->close;
    return;
}
