#!/usr/bin/perl

use strict;
use warnings;
no warnings 'uninitialized';

use Yote;
use Yote::Server;

use CGI;
use DateTime;
use Data::Dumper;
use JSON;
use URI::Escape;

unless( $main::yote_server ) {
    eval('use Yote::ConfigData');
    my $yote_root_dir = $@ ? '/opt/yote' : Yote::ConfigData->config( 'yote_root' );
    unshift @INC, "$yote_root_dir/lib";

    my $options = Yote::Server::load_options( $yote_root_dir );

    $main::yote_server = new Yote::Server( $options );
#    $main::yote_server->ensure_locker;

}
my $cgi = CGI->new;

my $json_payload = uri_unescape(scalar($cgi->param('p')));

my $out_json;
eval {
    $out_json = $main::yote_server->invoke_payload( $json_payload );
};

if( $@ ) {
    print $cgi->header( -status => '400 BAD REQUEST' );
} else {
    print $cgi->header(
        -status => '200 OK',
        -type => 'text/json'
        );
    print $out_json;
    $main::yote_server->{STORE}->stow_all;
}
