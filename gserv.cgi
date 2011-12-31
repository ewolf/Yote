#!/usr/bin/perl

use strict;

use CGI;
use Data::Dumper;
use IO::Socket;
use JSON;

my( $ret );
eval {
    $ret = &main();
};
if( $ret ) {
    print "Content-Type: text/x-json\n\n({ \"err\" : \"$@\" })\n";
}
sub main {
    my $CGI = new CGI;
    my $param = $CGI->Vars;
#    print STDERR Data::Dumper->Dump( [\%ENV] );

    $param->{oi} =  $ENV{REMOTE_ADDR};

    my $sock = new IO::Socket::INET (
	PeerAddr => '127.0.0.1',
	PeerPort => '8008',
	Proto => 'tcp',
	);
    open( OUT, ">>/home/irrespon/logs/gserv_relay.log" );
    print OUT Data::Dumper->Dump(["incoming params from client ",$param]);
    print $sock join('&',map { "$_=$param->{$_}" } keys %$param )."\n";
    my $buf = <$sock>;
#    print STDERR Data::Dumper->Dump([$buf,$param,'startbuf']);
#    while( <$sock> ) {
#	$buf .= $_;
#	print STDERR Data::Dumper->Dump([$buf,'nextbuf']);
#    }
#    print $buf;
#    print STDERR Data::Dumper->Dump(["BUFF", $buf]);
    print OUT Data::Dumper->Dump(["server response ",$buf]);
    close OUT;
    print "Content-Type: application/json\n\n$buf";
    return 0;
} #main
