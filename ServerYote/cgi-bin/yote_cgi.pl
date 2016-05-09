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
    print STDERR Data::Dumper->Dump(["MAKING YOTE SERVER"]);
    eval('use Yote::ConfigData');
    my $yote_root_dir = $@ ? '/opt/yote' : Yote::ConfigData->config( 'yote_root' );

    my $options = Yote::Server::load_options( $yote_root_dir );

    $main::yote_server = new Yote::Server( $options );
    my $locker = $main::yote_server->{_locker};
    my $lc = $locker->client;
    unless( $lc->ping ) {
        $locker->start;
    }
    $main::yote_server->{STORE}{_locker} = $locker;
}

my $cgi = CGI->new;

use URI::Escape;
my $json_payload = uri_unescape(scalar($cgi->param('p')));

print STDERR Data::Dumper->Dump([$json_payload,"PAYL"]);
my $out_json;
eval {
    $out_json = $main::yote_server->invoke_payload( $json_payload );
};
#$out_json = '{"methods":{"Yote::ServerRoot":["update","fetch","fetch_root","create_token","fetch_app","init_root"]},"result":["2","v635993730"],"updates":[{"id":"2","cls":"Yote::ServerRoot","data":{}}]}';
print STDERR Data::Dumper->Dump(["GOTTAN OUT ($@)",$out_json,\@INC]);
if( $@ && 0 ) {
    print STDERR Data::Dumper->Dump([$@]);
    print $cgi->header( -status => '400 BAD REQUEST' );
} else {
    print $cgi->header(
        -status => '200 OK',
        -type => 'text/json'
        );
    print $out_json;
    $main::yote_server->{STORE}->stow_all;
}
print STDERR Data::Dumper->Dump(["OINK"]);
