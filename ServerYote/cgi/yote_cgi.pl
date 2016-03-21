#!/usr/bin/perl

use strict;
use warnings;
no warnings 'uninitialized';

use Yote;

use CGI;
use DateTime;
use Data::Dumper;


my $cgi = CGI->new;

# get obj_id, token, action, params
my( $obj_id, $token, $action, $params );

if( substr( $action, 0, 1 ) eq '_' ) {
    # private method, not allowed
}

my $server_root;
my $server_root_id = $server_root->{ID};

my $session = $server_root->_fetch_session( $token );

unless( $obj_id eq '_' || 
        $obj_id eq $server_root_id || 
        ( $obj_id > 0 && 
          $session && 
          $server_root->_getMay( $obj_id, $session->get__token ) ) ) {

    # tried to do an action on an object it wasn't handed. do a 404
    _log( "Bad Path : '$path'" );

    # CGI not sock
    $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
    $sock->close;
    
    exit;
}

my $in_params;
eval {
    $in_params = $self->__transform_params( $params, $token, $server_root );
};
