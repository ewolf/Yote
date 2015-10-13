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
    
    my $locks = new Lock::Server;
    unless( $locks->start ) {
        $locks->stop;
        BAIL_OUT( "Unable to start server '$locks->{error}'" );
    } 

    is( msg( "UNLOCK KEY1 LOCKER1" ), '0', "can't unlock what is not locked" );
    is( msg( "LOCK KEY1 LOCKER1" ), '1', "first lock success key1" );
    is( msg( "LOCK KEY2 LOCKER1" ), '1', "first lock success key2" );
    is( msg( "LOCK KEY1 LOCKER1" ), '0', "cannot relock key1" );
    is( msg( "UNLOCK KEY1 LOCKER1" ), '1', "first unlock success" );
    is( msg( "UNLOCK KEY1 LOCKER1" ), '0', "cant repeat unlock" );
    is( msg( "LOCK KEY2 LOCKER1" ), '1', "second lock unlocked" );

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
