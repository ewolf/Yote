#!/usr/bin/perl

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;

use lib '/opt/yote/lib';

use CGI;
use DateTime;
use Data::Dumper;
use JSON;

unless( $main::yote_server ) {
    eval('use Yote::ConfigData');
    my $yote_root_dir = $@ ? '/opt/yote' : Yote::ConfigData->config( 'yote_root' );

    my $options = Yote::Server::load_options( $yote_root_dir );

    $main::yote_server = new Yote::Server( $options );
    my $locker = $main::yote_server->{_locker};
    my $lc = $locker->client("CGI");
    unless( $lc->ping(1) ) {
        $locker->start;
    }
    $main::yote_server->{STORE}{_locker} = $locker;
}
my $cgi = CGI->new;

use URI::Escape;
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
