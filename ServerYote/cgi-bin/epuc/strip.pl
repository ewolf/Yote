#!/usr/bin/perl

use strict;
use warnings;
no warnings 'uninitialized';

use lib '/opt/yote/lib';
use lib '/home/wolf/proj/Yote/ServerYote/lib';
use lib '/home/wolf/proj/Yote/LockServer/lib';
use lib '/home/wolf/proj/Yote/FixedRecordStore/lib';
use lib '/home/wolf/proj/Yote/YoteBase/lib';

use Yote;
use Yote::Server;
use EPUC::Util;

my( $server, $cgi ) = EPUC::Util::init;
# Käse essen
my $app = $server->fetch_app( 'EPUC::App' );

my $strip_id = $cgi->param('s');
my $strip_id = $cgi->param('s');

my $strip = $server->store->_fetch( $strip_id );

if( $strip ) {
    # find the index of the strip and make sure it is ready
    if( $strip->get__state eq 'complete' ) {
        my $strips = 
    }
}

print $cgi->header(
    -status => '200 OK',
    -type => 'text/json'
    );
_log("OUTY <$out_json>");
print $out_json;
$main::yote_server->{STORE}->stow_all;


