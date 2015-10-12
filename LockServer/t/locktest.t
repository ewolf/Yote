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

my $locks = new Lock::Server( { 
    lock_timeout         => 4,  
    lock_attempt_timeout => 5,  
                              } );
unless( $locks->start ) {
    my $err = $locks->{error};
    $locks->stop;
    BAIL_OUT( "Unable to start server '$err'" );
} 


test_suite();

$locks->stop;

done_testing;

exit( 0 );


sub test_suite {
    
    my $locker1 = $locks->client( "LOCKER1" );
    is( $locker1->isLocked( "KEY1" ), '0', "KEY1 LOCKER1 not locked by anyone" );
    is( $locker1->lockedByMe( "KEY1" ), '0', "KEY1 LOCKER1 reported as not locked before any locking" );
    is( $locker1->unlock( "KEY1" ), '0', "can't unlock what is not locked KEY1 LOCKER1" );
    cmp_ok( $locker1->lock( "KEY1" ), '>', '1', "lock KEY1 LOCKER1" );
    is( $locker1->isLocked( "KEY1" ), '1', "KEY1 LOCKER1 reported as locked" );
    is( $locker1->lockedByMe( "KEY1" ), '1', "KEY1 LOCKER1 reported as locked after locking" );
    cmp_ok( $locker1->lock( "KEY2" ), '>', '1', "lock KEY2 LOCKER1" );
    is( $locker1->isLocked( "KEY2" ), '1', "KEY2 LOCKER1 reported as locked" );
    is( $locker1->lockedByMe( "KEY2" ), '1', "KEY2 LOCKER1 reported as locked after locking" );
    is( $locker1->lock( "KEY1" ), '0', "cannot relock KEY1 LOCKER1" );
    is( $locker1->lockedByMe( "KEY1" ), '1', "KEY1 LOCKER1 reported as locked after locking" );
    is( $locker1->unlock( "KEY1" ), '1', "first unlock KEY1 LOCKER1" );
    is( $locker1->lockedByMe( "KEY1" ), '0', "KEY1 LOCKER1 reported as not locked after unlocking" );
    is( $locker1->lockedByMe( "KEY2" ), '1', "KEY2 LOCKER1 reported as locked after locking" );
    is( $locker1->unlock( "KEY1" ), '0', "cant repeat unlock KEY1 LOCKER1" );
    is( $locker1->lockedByMe( "KEY1" ), '0', "KEY1 LOCKER1 reported as not locked after unlocking twice" );
    is( $locker1->unlock( "KEY2" ), '1', "second lock unlocked KEY2 LOCKER1" );
    is( $locker1->lockedByMe( "KEY1" ), '0', "KEY1 LOCKER1 reported as not locked by me after unlocking" );
    is( $locker1->lockedByMe( "KEY2" ), '0', "KEY2 LOCKER1 reported as not locked by me after unlocking" );
    is( $locker1->isLocked( "KEY2" ), '0', "KEY2 LOCKER1 reported as not locked" );


    # see if one process waits on the other
    my( @pids );
    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        # if I actually use the test framework, it loses track of how many
        # tests there are and has a strange failusre
        my $locker3 = $locks->client( "LOCKER3" );
        my $res = $locker3->lock( "KEY1" ) > 1 &&
            $locker3->isLocked( "KEY1" ) == 1 &&
            $locker3->lockedByMe( "KEY1" ) == 1;
        sleep 2;
        $res = $res && $locker3->unlock( "KEY1" ) == 1;

        exit ! $res;
    }
    
    sleep .1;
    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        my $locker4 = $locks->client( "LOCKER4" );
        my $res = $locker4->isLocked( "KEY1" ) == 1;
        # KEY1 is locked by locker3, so this doesn't return until it
        # is unlocked, a time of 2 seconds
        $res = $res && $locker4->lock( "KEY1" ) > 1 &&
            $locker4->unlock( "KEY1" ) == 1;
         exit ! $res;
    }

    my $t1 = time;
    while( @pids ) { 
        my $pid = shift @pids;
        waitpid $pid, 0;
        fail( "Child Proc Test Failed '$?'" ) if $?;
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
        $res = $res && $locker4->isLocked( "KEYB" ) == 0 &&
            $locker4->lock( "KEYB" ) > 1 &&
            $locker4->unlock( "KEYB" ) == 1;
         exit ! $res;
    }
    sleep .01;
    if( my $pid = fork ) {
        push @pids, $pid;
    } else {
        my $locker5 = new Lock::Server::Client( "LOCKER5", '127.0.0.1', 8004 );
        my $res = $locker5->lock( "KEYB" ) > 1 &&
            $locker5->lockedByMe( "KEYB" ) == 1;
        my $t = time;
        $res = $res && $locker5->lockedByMe( "KEYA" ) == 0 &&
            $locker5->lock( "KEYA" ) == 0 &&
            $locker5->lockedByMe( "KEYB" ) == 0 &&
            (time-$t) == 5;
        exit( ! $res );
    }
    
    while( @pids ) { 
        my $pid = shift @pids;
        waitpid $pid, 0;
        fail( "Child Proc Test Failed '$?'" ) if $?;
    }
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