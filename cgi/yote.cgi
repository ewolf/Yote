#!/usr/bin/env perl

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

    local $SIG{ALRM} = sub { 
        print "Content-Type: application/json\n\n".to_json( { err => "timeout from server" } );
    };

    alarm(3);

    $param->{oi} =  $ENV{REMOTE_ADDR};

    my $sock = new IO::Socket::INET (
        PeerAddr => '127.0.0.1',
        PeerPort => '8008',
        Proto => 'tcp',
        );

    print $sock join('&',map { "$_=$param->{$_}" } keys %$param )."\n";
    my $buf = <$sock>;
    print "Content-Type: application/json\n\n$buf";
    alarm(0);
    return 0;
} #main
