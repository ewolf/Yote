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
$Lock::Server::DEBUG = 0;
test_suite();
done_testing;

exit( 0 );


sub test_suite {
    
    my $locks = new Lock::Server( { 
        lock_timeout         => 4,  
        lock_attempt_timeout => 5,  
     } );
    unless( $locks->start ) {
	my $err = $locks->{error};
        $locks->stop;
        BAIL_OUT( "Unable to start server '$err'" );
    } 

    is( msg( "UNLOCK KEY1 LOCKER1" ), '0', "can't unlock what is not locked KEY1 LOCKER1" );
    is( msg( "LOCK KEY1 LOCKER1" ), '1', "lock KEY1 LOCKER1" );
    is( msg( "LOCK KEY2 LOCKER1" ), '1', "lock KEY2 LOCKER1" );
    is( msg( "LOCK KEY1 LOCKER1" ), '0', "cannot relock KEY1 LOCKER1" );
    is( msg( "UNLOCK KEY1 LOCKER1" ), '1', "first unlock KEY1 LOCKER1" );
    is( msg( "UNLOCK KEY1 LOCKER1" ), '0', "cant repeat unlock KEY1 LOCKER1" );
    is( msg( "UNLOCK KEY2 LOCKER1" ), '1', "second lock unlocked KEY2 LOCKER1" );

    my( @pids );

    # see if one process waits on the other

    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        is( msg( "LOCK KEY1 LOCKER3" ), '1', "lock KEY1 LOCKER3" );
        sleep 2;
        is( msg( "UNLOCK KEY1 LOCKER3" ), '1', "unlock KEY1 LOCKER3" );
        exit;
    }
    sleep .01;
    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        # KEY1 is locked by locker3, so this doesn't return until it
        # is unlocked, a time of 2 seconds
        is( msg( "LOCK KEY1 LOCKER4" ), '1', "lock KEY1 LOCKER4" );
        is( msg( "UNLOCK KEY1 LOCKER4" ), '1', "unlock KEY1 LOCKER4" );
        exit;
    }

    my $t1 = time;
    while( @pids ) { 
        my $pid = shift @pids;
        waitpid $pid, 0;
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
        is( msg( "LOCK KEYA LOCKER4" ), '1', "lock KEYA LOCKER4" ); #A locked
        sleep 5;
        is( msg( "LOCK KEYB LOCKER4" ), '1', "LOCK KEYB LOCKER4" ); #B lock released when second thread failed
        is( msg( "UNLOCK KEYB LOCKER4" ), '1', "unlock KEYB LOCKER4" );
        exit;
    }
    sleep .01;
    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        is( msg( "LOCK KEYB LOCKER5" ), '1', "lock KEYB LOCKER5" ); #B locked
        my $t = time;
        is( msg( "LOCK KEYA LOCKER5" ), '0', "KEY1 LOCKER5 deadlocked out" );
        is( time-$t, 5, "deadlock timed out " );
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
