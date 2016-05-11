use strict;
use warnings;
no warnings 'uninitialized';
no warnings 'numeric';

use Data::Dumper;
use File::Temp qw/ :mktemp tempdir /;
use JSON;
use Test::More;

use Carp;

BEGIN {
    use_ok( "Yote::Server" ) || BAIL_OUT( "Unable to load Yote::Server" );
    $Yote::Server::DEBUG = -1;
    no strict 'refs';
    *Yote::ServerRoot::test = sub {
        my( $self, @args ) = @_;
        return ( "FOOBIE", "BLECH", @args );
    };
    *Yote::ServerObj::someMethod = sub {
        my( $self, @args ) = @_;
        return ( "FOOBIE", "BLECH", @args );
    };
    use strict 'refs';    
}

my $dir = tempdir( CLEANUP => 1 );
my $server = new Yote::Server( { yote_root_dir => $dir, yote_port => 8881 } );
my $store = $server->{STORE};
my $otherO = $store->newobj;
my $root = $store->fetch_server_root;
$root->set_fooObj( $store->newobj( { innerfoo => [ 'innerbar', 'vinnercar', $otherO ] } ) );
my $fooHash = $root->set_fooHash( {  innerFooHash => $otherO, someTxt => "vvtxtyTxt"} );
my $fooArr = $root->set_fooArr( [ $otherO, 'vinner', 'winnyo'] );
$root->set_txt( "SOMETEXT" );
my $fooObj   = $root->get_fooObj;
my $innerfoo = $fooObj->get_innerfoo;
$store->stow_all;

#use Devel::SimpleProfiler;
#Devel::SimpleProfiler::init( '/tmp/foobar', qr/Yote::[^O]|Lock|Data|test_suite/ );
#Devel::SimpleProfiler::start;

my( $pid, $count );
until( $pid ) {
    $pid = $server->start;
    last if $pid;
    sleep 5;
    if( ++$count > 10 ) {
        my $err = $server->{error};
        $server->stop;
        BAIL_OUT( "Unable to start server '$err'" );
    }
} 

$SIG{ INT } = $SIG{ __DIE__ } =
    sub {
        $server->stop;
        Carp::confess( @_ );
};

sleep 1;

test_suite();

$server->stop;

done_testing;

#print Devel::SimpleProfiler::analyze('calls');

exit( 0 );

sub msg {  #returns resp code, headers, response pased from json 
    my( $obj_id, $token, $action, @params ) = @_;
    
    my $socket = new IO::Socket::INET( "127.0.0.1:8881" ) or die "Error contacting server : $@";
    my $payload = 'p=' . to_json( {
        i => $obj_id,
        t => $token,
        a => $action,
        pl => [map { $_ > 1 || substr($_,0,1) eq 'v' ? $_ : "v$_" } @params],
                           } );
    $socket->print( "POST / HTTP/1.1\nContent-Type: text/json\nContent-Length: " . length( $payload ) ."\n\n$payload" );
    
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
    if( $hdr{'Content-Length'} ) {
        my $rtxt = '';
        while( $resp = <$socket> ) {
            $rtxt .= $resp;
        }
        $ret = from_json( $rtxt );
    }
    return ( $code, \%hdr, $ret );
}

sub l2a {
    # converts a list to a hash ref
    my $params = ref( $_[0] ) ? $_[0] : [ @_ ];
    return { map { $_ => 1 } @$params };
}

sub test_suite {
    
    my( @pids );

    # try no token, and with token
    my( $retcode, $hdrs, $ret ) = msg( '_', '_', 'test' );
    is( $retcode, 200, "root node can call test" );
    is_deeply( $hdrs, {
        'Content-Length' => '57',
        'Access-Control-Allow-Headers' => 'accept, content-type, cookie, origin, connection, cache-control',
        'Server' => 'Yote',
        'Access-Control-Allow-Origin' => '*',
        'Content-Type' => 'text/json; charset=utf-8'
        }, 'correct headers returned' );


    ( $retcode, $hdrs, $ret ) = msg( '_', '_', 'noMethod' );
    is( $retcode, 400, "root node has no noMethod call" );
    ok( ! $ret, "nothing returned for error case noMethod" );


    ( $retcode, $hdrs, $ret ) = msg( $root->{ID}, '_', 'test' );
    is( $retcode, 200, "no access without token when calling by id for server root only" );
    is_deeply( $ret->{methods}, {}, 'correct methods (none) for server root with non fetch_root call (called test)' );
    is_deeply( $ret->{updates}, [], "no updates without token" );

    ( $retcode, $hdrs, $ret ) = msg( $root->{ID}, '_', 'fetch_root' );
    is( $retcode, 200, "no access without token when calling by id for server root only" );

    ok( $ret->{methods}{'Yote::ServerRoot'}, "has methods for server root" );

    is_deeply( l2a( $ret->{methods}{'Yote::ServerRoot'} ),
               l2a( qw(  create_token
                         fetch_app
                         fetch_root
                         init_root
                         test
                         update
                  ) ), 'correct methods for fetched server root' );

    is_deeply( $ret->{updates}, [{cls  => 'Yote::ServerRoot', 
                                  id   => $root->{ID}, 
                                  data => {
                                      txt     => 'vSOMETEXT',
                                      fooObj  => $store->_get_id( $fooObj ),
                                      fooHash => $store->_get_id( $fooHash ),
                                      fooArr  => $store->_get_id( $fooArr ),
                                  } }], "updates for fetch_root by id, no token" );

    # now try with a token
    ( $retcode, $hdrs, $ret ) = msg( $root->{ID}, '_', 'create_token' );
    is( $retcode, 200, "token was returned" );
    my( $token ) = map { substr( $_, 1 ) }  @{ $ret->{result} };
    cmp_ok( $token, '>', 0, "Got token" );
    is_deeply( $ret->{updates}, [], "no updates when calling create token" );
    is_deeply( $ret->{methods}, {}, 'no methods returned for creat token ' );

    ( $retcode, $hdrs, $ret ) = msg( $root->{ID}, $token, 'fetch_root' );
    is( $retcode, 200, "able to return with token" );

    ok( $ret->{methods}{'Yote::ServerRoot'}, "has methods for server root" );
    is( scalar( keys %{$ret->{methods}} ), 2, "root methods and serverobj methods methods returned" );
    is_deeply( l2a( $ret->{methods}{'Yote::ServerRoot'} ),
               l2a( qw( create_token
                        fetch_app
                        fetch_root
                        init_root
                        test
                        update
                    ) ), 'correct methods for server root' );



    # make sure no prive _ method is called.
    ( $retcode, $hdrs, $ret ) = msg( $root->{ID}, $token, '_updates_needed' );
    is( $retcode, 400, "cannot call underscore method" );

    # make sure no nonexistant method is called.
    ( $retcode, $hdrs, $ret ) = msg( $root->{ID}, $token, 'slurpyfoo' );
    is( $retcode, 400, "cannot call nonexistant method" );


    ( $retcode, $hdrs, $ret ) = msg( $root->{ID}, $token, 'update' );

    $root->set_extra( "WOOF" );
#
    sleep 2;
    $store->stow_all;

# ok, server root wasn't reloaded because it doesn't do that. Maybe that is bad. set an other extra?

    # get the 'foo' object off of the root
    ( $retcode, $hdrs, $ret ) = msg( $root->{ID}, $token, 'update' );
    is( $retcode, 200, "able to fetch allowed object" );
    is_deeply( $ret->{updates}, [{cls  => 'Yote::ServerRoot', 
                                  id   => $root->{ID}, 
                                  data => {
                                      extra   => 'vWOOF',
                                      txt     => 'vSOMETEXT',
                                      fooObj  => $store->_get_id( $fooObj ),
                                      fooHash => $store->_get_id( $fooHash ),
                                      fooArr  => $store->_get_id( $fooArr ),
                                  } } ], "updates for fetch_root by id token after change and save" );



    # try to call a method without a token
    
    

    # finally get a token


    while( @pids ) { 
        my $pid = shift @pids;
        waitpid $pid, 0;

        # XXX
        fail("Killing pid failed : $@") if $?;
    }
    
} #test suite

__END__
