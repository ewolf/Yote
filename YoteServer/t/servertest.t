use strict;
use warnings;
no warnings 'uninitialized';

use Data::Dumper;
use JSON;
use Test::More;
#Test::More->builder->no_ending(1);

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    use_ok( "Yote::Server" ) || BAIL_OUT( "Unable to load Yote::Server" );
}

my $server = new Yote::Server;

unless( $server->start ) {
    my $err = $server->{error};
    $server->stop;
    BAIL_OUT( "Unable to start server '$err'" );
} 


test_suite();

$server->stop;

done_testing;

exit( 0 );

sub msg {  #returns resp code, headers, response pased from json 
    my( $obj_id, $action, $token, @params ) = @_;
    
    my $socket = new IO::Socket::INET(
        Listen    => 10,
        LocalAddr => "127.0.0.1:8881",
        );
    $socket->print( "GET " . join( '/',  $obj_id, $token, $action, @params ) . " HTTP/1.1" );

    my $resp = <$socket>;
    
    my( $code ) = ( $resp =~ /^HTT[^ ]+ (\d+) / ) ;
    
    # headers
    my %hdr;
    while( $resp = <$socket> ) {
        chomp $resp;
        last unless $resp =~ /\S/s;
        my( $k, $v ) = ( $resp =~ /(.*)\s*:\s*(.*)/ );
        $hdr{$k} = $v;
    }
    my $ret;
    if( $hdr->{'Content-Length'} ) {
        my $rtxt = '';
        while( $resp = <$socket> ) {
            $rtxt .= $resp;
        }
        $ret = from_json( $rtxt );
    }
    return ( $code, \%hdr, $ret );
}

sub test_suite {
    
    my( @pids );

    # try no token, and with token
    my( $retcode, $hdrs, $ret ) = msg( '_', '_', '

    # make sure no prive _ method is called.


    while( @pids ) { 
        my $pid = shift @pids;
        waitpid $pid, 0;

        # XXX
        fail("LOCKER4/LOCKER5") if $?;
    }
    
} #test suite

__END__
