#!/usr/bin/perl -w
#
# dummyhttpd - start an HTTP daemon and print what the client sends

use strict;
use HTTP::Daemon;  # need LWP-5.32 or better
my $server;
eval {
    $server = HTTP::Daemon->new(Timeout => 60, LocalPort => 8008);
};
if( $@ ) {
    print STDERR Data::Dumper->Dump([$@]);
}
print "Please contact me at: <URL:", $server->url, ">\n";

while (my $client = $server->accept) {
    CONNECTION:
    while (my $answer = $client->get_request) {
        print $answer->as_string;
        $client->autoflush;
	RESPONSE:
        while (<STDIN>) {
            last RESPONSE   if $_ eq ".\n";
            last CONNECTION if $_ eq "..\n";
            print $client $_;
        }
        print "\nEOF\n";
    }
    print "CLOSE: ", $client->reason, "\n";
    $client->close;
    undef $client;
}
