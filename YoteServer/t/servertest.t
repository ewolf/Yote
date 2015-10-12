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

sub msg {
    my( $obj_id, $action, $token, @params ) = @_;
    
    my $socket = new IO::Socket::INET(
        Listen    => 10,
        LocalAddr => "127.0.0.1:8881",
        );
    $socket->print( "GET " . join( '/',  $obj_id, $token, $action, @params ) . " HTTP/1.1" );
    
}

sub test_suite {
    
    my( @pids );

    my $locker1 = $locks->client( "LOCKER1" );

    # see if one process waits on the other

    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        my $locker3 = $locks->client( "LOCKER3" );
        $res = $res && $locker3->unlock( "KEY1" ) == 1;
        exit ! $res;
    }
    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        print STDERR "starting first client\n";
        my $locker4 = $locks->client( "LOCKER4" );
        my $res = $locker4->isLocked( "KEY1" ) == 1;
        exit ! $res;
    }

    my $t1 = time;
    while( @pids ) { 
        my $pid = shift @pids;
        waitpid $pid, 0;

        # XXX
        fail("LOCKER4") if $?;

    }
    is( int(time -$t1),2, "second lock waited on the first" );

    # deadlock timeouts

    # 4 locks A
    # 5 locks B
    # 5 tries to lock A
    # 2 seconds happen
    

    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        my $locker4 = $locks->client( "LOCKER4" );
        my $res = $locker4->lock( "KEYA" ) > 1;
        sleep 5;
        $res = $res && $locker4->isLocked( "KEYB" ) == 0;
        $res = $res && $locker4->lock( "KEYB" ) > 1;
        $res = $res && $locker4->unlock( "KEYB" ) == 1;
        exit ! $res;

    }
    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        print STDERR "starting second client\n";
        my $locker5 = new Lock::Server::Client( "LOCKER5", '127.0.0.1', 8004 );
        my $res = $locker5->lock( "KEYB" ) > 1;
        $res = $res && $locker5->lockedByMe( "KEYB" ) == 1;
        my $t = time;
        $res = $res && $locker5->lockedByMe( "KEYA" ) == 0;
        $res = $res && $locker5->lock( "KEYA" ) == 0;
        $res = $res && $locker5->lockedByMe( "KEYB" ) == 0;
        $res = $res && ( time-$t ) == 5;
        exit ! $res;
    }

    while( @pids ) { 
        my $pid = shift @pids;
        waitpid $pid, 0;

        # XXX
        fail("LOCKER4/LOCKER5") if $?;
    }
    
} #test suite

__END__
