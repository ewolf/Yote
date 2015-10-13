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
    
    my $locks = new Lock::Server;
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

    if( my $pid = fork ) {
	push @pids, $pid;
	is( msg( "LOCK KEY1 LOCKER3" ), '1', "first lock success key1" );
    }

    if( my $pid = fork ) {
	push @pids, $pid;
	is( msg( "LOCK KEY1 LOCKER4" ), '1', "first lock success key1" );
    }

    while( @pids ) { 
	my $pid = shift @pid;
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
