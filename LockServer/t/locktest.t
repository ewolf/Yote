use strict;
use warnings;
no warnings 'uninitialized';

use Lock::Server;

use Data::Dumper;
use Test::More;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    use_ok( "Lock::Server" ) || BAIL_OUT( "Unable to load Lock::Server" );
}
$Lock::Server::DEBUG = 1;
test_suite();
done_testing;

exit( 0 );


sub test_suite {
    
    my $locks = new Lock::Server( { lock_timeout => 3 } );
    unless( $locks->start ) {
	my $err = $locks->{error};
        $locks->stop;
        BAIL_OUT( "Unable to start server '$err'" );
    } 

    is( msg( "UNLOCK KEY1 LOCKER1" ), '0', "can't unlock what is not locked" );
    is( msg( "LOCK KEY1 LOCKER1" ), '1', "first lock success key1" );
    is( msg( "LOCK KEY2 LOCKER1" ), '1', "first lock success key2" );
    is( msg( "LOCK KEY1 LOCKER1" ), '0', "cannot relock key1" );
    is( msg( "UNLOCK KEY1 LOCKER1" ), '1', "first unlock success" );
    is( msg( "UNLOCK KEY1 LOCKER1" ), '0', "cant repeat unlock" );
    is( msg( "UNLOCK KEY2 LOCKER1" ), '1', "second lock unlocked" );

    my( @pids );

    # see if one process waits on the other

    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        is( msg( "LOCK KEY1 LOCKER3" ), '1', "first lock success key1" );
        sleep 2;
        is( msg( "UNLOCK KEY1 LOCKER3" ), '1', "first unlock success key1" );
        exit;
    }
    sleep .01;
    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        # KEY1 is locked by locker3, so this doesn't return until it
        # is unlocked, a time of 2 seconds
        is( msg( "LOCK KEY1 LOCKER4" ), '1', "second lock success key1" );
        is( msg( "UNLOCK KEY1 LOCKER4" ), '1', "second unlock success key1" );
        exit;
    }

    my $t1 = time;
    while( @pids ) { 
        my $pid = shift @pids;
        waitpid $pid, 0;
    }
    is( int(time -$t1),2, "second lock waited on the first" );

    # deadlock detection
    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        is( msg( "LOCK KEYA LOCKER4" ), '1', "first lock success keya" );
        sleep 2;
        is( msg( "LOCK KEYB LOCKER4" ), '1', "first lock success keyb" );
        exit;
    }
    sleep .01;
    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        is( msg( "LOCK KEYB LOCKER5" ), '1', "second lock success keya" );
        my $t = time;
        is( msg( "LOCK KEYA LOCKER5" ), '0', "second lock success keyb" );
        is( time-$t, 3, "deadlock timed out " );
        exit;
    }

    while( @pids ) { 
        my $pid = shift @pids;
        waitpid $pid, 0;
    }
    
    $locks->stop;

} #test suite

sub msg {
    my( $msg ) = @_;
    my $sock = new IO::Socket::INET( "127.0.0.1:8004" );
    $sock->autoflush;
    $sock->print( "$msg\n" );
    my $answer = <$sock>;
    $sock->close;
    chomp $answer;
    return $answer;
}

__END__
