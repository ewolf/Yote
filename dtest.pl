use strict;

use Data::Dumper;

use Daemon::Daemonize qw/ :all /;

my $pf = "/tmp/dtest.pid";

my $arg = shift @ARGV;

print "DOING $arg\n";

if( $arg eq 'stop' ) {
    if( my $pid = check_pidfile( $pf ) ) {
        print "Stopping $0\n";
        kill 'SIGINT', $pid;
        sleep 2;
        print "Done\n";
        exit;
    }    
    print "dtest is not running\n";
    exit;
}

if( $arg eq 'start' ) {
    if( check_pidfile( $pf ) ) {
        print "dtest is already running\n";
        exit;
    }
    start_dtest();
    exit;
}

if( $arg eq 'restart' ) {
    if( my $pid = check_pidfile( $pf ) ) {
        print "Stopping $0\n";
        kill 'SIGINT', $pid;
        sleep 2;
        print "Done\n";
    }    
    start_dtest();
    exit;
}
if( $arg eq 'status' ) {
    print check_pidfile( $pf ) ? "dtest is running\n" : "dtest is not running\n";
    exit;
}
# default is to report that it is running or run it
if( my $pid = check_pidfile( $pf ) ) {
    print "dtest is running\n";
} else {
    start_dtest();
}

exit;

my %procs;
my $in_shutdown = 0;

sub start_dtest {
    daemonize( close => 0 );
    write_pidfile( $pf );

    $SIG{ INT } = $SIG{ TERM } = sub {
        print STDERR "Got term or int signal\n";
        $in_shutdown = 1;
        for my $cpid (keys %procs) {
            kill 'SIGINT', $cpid;
        }
        sleep 1;
        while( (my $cpid = waitpid( -1, 0 )) > 0 ) {
            print "killz > $cpid\n";
            delete $procs{ $cpid };
        }
        print STDERR "cleaned up\n";
    };

    for( 1..5 ) {
        startchld();
    }
    $0 = 'dtest';
    print "Started dtest\n";

    while( ! $in_shutdown ) {
        my $cpid = waitpid( -1, 0 );
        if( $cpid > 0 ) {
            delete $procs{ $cpid };
            startchld();
        }        
    }
    print "Exiting program\n";
}

sub startchld {
    my $cpid = fork;
    if( $cpid > 0 ) {
        $procs{ $cpid } = 1;
    } elsif( defined $cpid ) { #child
        print "New Worker\n";
        $0 = 'dtest child';
        $SIG{ INT } = sub { print STDERR "Child proc $$ got int. exiting\n"; exit; };
        $SIG{ TERM } = sub { print STDERR "Child proc $$ got term. exiting\n"; exit; };
        $SIG{ __DIE__ } = sub { print STDERR "Child proc $$ got die. exiting\n"; exit; };
        while( 1 ) {
            sleep 5 + int( 10 * rand() );
            print "Child proc $$ did something\n";
        }
    } else {
        print STDERR "Unable to fork process\n";
    }
}
