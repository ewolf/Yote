#!/usr/bin/perl

use strict;
use warnings;
no warnings 'uninitialized';


# use lib qw( /home/wolf/proj/Yote/LockServer/lib
#             /home/wolf/proj/Yote/ServerYote/lib
#             /home/wolf/proj/Yote/YoteBase/lib 
#             /opt/yote/lib
#            );


use CGI;
use DateTime;
use Data::Dumper;
use JSON;
use URI::Escape;

print STDERR Data::Dumper->Dump(["HI REEQ",\@INC]);

unless( $main::yote_root_dir ) {
    eval('require Yote::ConfigData');
    $main::yote_root_dir = $@ ? '/opt/yote' : Yote::ConfigData->config( 'yote_root' );
}
unshift @INC, "$main::yote_root_dir/lib";
unshift @INC, qw( /home/wolf/proj/Yote/LockServer/lib
             /home/wolf/proj/Yote/ServerYote/lib
             /home/wolf/proj/Yote/YoteBase/lib 
             /opt/yote/lib
);

unless( $main::yote_server ) {
    eval('require Yote::Server');

    eval('require Yote::Server');
    my $options = Yote::Server::load_options( $main::yote_root_dir );

    $main::yote_server = new Yote::Server( $options );
#    $main::yote_server->ensure_locker;

}
$SIG{TERM} = $SIG{INT} = sub {
    print STDERR "OH NO CABOOSE\n\n";
    if( $main::yote_server ) {
#        $main::yote_server->{_locker}->stop;
    }
};

my $cgi = CGI->new;

my $json_payload = uri_unescape(scalar($cgi->param('p')));

my $out_json;
eval {
    $out_json = $main::yote_server->invoke_payload( $json_payload );
};
print STDERR Data::Dumper->Dump(["DUMPY3",$@]);

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
