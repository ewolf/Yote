use strict;
use warnings;
no warnings 'uninitialized';

use Data::Dumper;
use File::Temp qw/ :mktemp tempdir /;
use JSON;
use Test::More;

use Carp;

BEGIN {
    use_ok( "Yote::Server" ) || BAIL_OUT( "Unable to load Yote::Server" );
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
my $server = new Yote::Server( { yote_root_dir => $dir } );
my $store = $server->{STORE};

my $root = $store->fetch_server_root;
$root->set_foo( $store->newobj( { innerfoo => [ 'innerbar', 'innercar' ] } ) );
my $foo      = $root->get_foo;
my $innerfoo = $foo->get_innerfoo;


my $pid = $server->start;
unless( $pid ) {
    my $err = $server->{error};
    $server->stop;
    BAIL_OUT( "Unable to start server '$err'" );
} 

$SIG{ INT } = $SIG{ __DIE__ } =
    sub {
        $server->stop;
        Carp::confess( @_ );
};

sleep 1;


test_suite();

print STDERR Data::Dumper->Dump(["STOPPING"]);
$server->stop;

done_testing;

exit( 0 );

sub msg {  #returns resp code, headers, response pased from json 
    my( $obj_id, $token, $action, @params ) = @_;
    
    my $socket = new IO::Socket::INET( "127.0.0.1:8881" ) or die "FOO $@";
    $socket->print( "GET /" . join( '/',  $obj_id, 
                                    $token, 
                                    $action, 
                                    map {  int($_) > 1 ? $_ : "v$_" } @params ) . 
                    " HTTP/1.1\n\n" );
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
    # converts a list to an array
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



    ( $retcode, $hdrs, $ret ) = msg( '2', '_', 'test' );
    is( $retcode, 200, "no access without token when calling by id for server root only" );

    ( $retcode, $hdrs, $ret ) = msg( '2', '_', 'fetch_root' );
    is( $retcode, 200, "no access without token when calling by id for server root only" );

    ok( $ret->{methods}{'Yote::ServerRoot'}, "has methods for server root" );

    is_deeply( l2a( $ret->{methods}{'Yote::ServerRoot'} ),
               l2a( qw( fetch_app
                         fetch
                         test
                         fetch_root
                         create_token
                    ) ), 'correct methods for server root' );

    # now try with a token
    ( $retcode, $hdrs, $ret ) = msg( '2', '_', 'create_token' );
    is( $retcode, 200, "token was returned" );
    my( $token ) = map { substr( $_, 1 ) }  @{ $ret->{result} };
    cmp_ok( $token, '>', 0, "Got token" );
    ok( $ret->{methods}{'Yote::ServerRoot'}, "has methods for server root" );
    is_deeply( [keys %{$ret->{updates}[0]{data}}], [ 'foo' ], "data has foo" );
    is_deeply( l2a( $ret->{methods}{'Yote::ServerRoot'} ),
               l2a( qw( fetch_app
                         fetch
                         test
                         fetch_root
                         create_token
                    ) ), 'correct methods for server root' );


    ( $retcode, $hdrs, $ret ) = msg( '2', $token, 'fetch_root' );
    is( $retcode, 200, "able to return with token" );

    ok( $ret->{methods}{'Yote::ServerRoot'}, "has methods for server root" );

    is_deeply( l2a( $ret->{methods}{'Yote::ServerRoot'} ),
               l2a( qw( fetch_app
                         fetch
                         test
                         fetch_root
                         create_token
                    ) ), 'correct methods for server root' );



    ( $retcode, $hdrs, $ret ) = msg( '2', $token, 'fetch_root' );
    is( $retcode, 200, "no access without token when calling by id for server root only" );

    is_deeply( $ret->{updates}, [], "no updates needed known" );
    is_deeply( $ret->{methods}, [], "methods already known" );

    # make sure no prive _ method is called.
    ( $retcode, $hdrs, $ret ) = msg( '2', $token, '_updates_needed' );
    is( $retcode, 400, "cannot call underscore method" );

    # make sure no nonexistant method is called.
    ( $retcode, $hdrs, $ret ) = msg( '2', $token, 'slurpyfoo' );
    is( $retcode, 400, "cannot call nonexistant method" );

    # directly fetch the innerfoo. should work as the innerfoo id had
    # not been returned to the client
    print STDERR "\n\n-------------------------------------------------\n\n";

    print STDERR Data::Dumper->Dump([$store->_get_id( $innerfoo ), "ID" ]);

    ( $retcode, $hdrs, $ret ) = msg( '2', $token, 'fetch', $store->_get_id( $innerfoo ) );
    print STDERR Data::Dumper->Dump([$retcode,$hdrs,$ret,'fi']);

    ( $retcode, $hdrs, $ret ) = msg( '2', $token, 'fetch', $foo->{ID} );
    print STDERR Data::Dumper->Dump([$retcode,$hdrs,$ret,'fo']);return;

    # get the 'foo' object off of the root
    ( $retcode, $hdrs, $ret ) = msg( '2', '_', 'get', 'foo' );


    # get the 'foo' object off of the root
    ( $retcode, $hdrs, $ret ) = msg( '2', '_', 'get', 'foo' );
    


    print STDERR Data::Dumper->Dump([$retcode,$hdrs,$ret,'get']);

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
