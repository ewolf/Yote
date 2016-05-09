#!/usr/bin/perl

use strict;
use warnings;
no warnings 'uninitialized';

use Yote;

use CGI;
use DateTime;
use Data::Dumper;
use JSON;

unless( $main::yote_server ) {
    eval('use Yote::ConfigData');
    my $yote_root_dir = $@ ? '/opt/yote' : Yote::ConfigData->config( 'yote_root' );

    my $options = Yote::Server::load_options( $yote_root_dir );

    $main::yote_server = new Yote::Server( $options );
}


my $cgi = CGI->new;

my $json_payload = $cgi->param('p');

my $out_json;
eval {
    $out_json = $main::yote_server->invoke_payload( $json_payload );
};
if( $@ ) {
    print $cgi->header( -status => '400 BAD REQUEST' );
} else {
    print $cgi->header( 'text/json' );
    print $out_json;
}
