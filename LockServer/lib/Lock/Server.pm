package Lock::Server;

use strict;
use warnings;
no warnings 'uninitialized';

use IO::Socket::INET;

$Lock::Server::DEBUG = 0;

sub new {
    my( $pkg, $args ) = @_;
    my $class = ref( $pkg ) || $pkg;
    bless {
	pids		=> {},
        id2pid        => {},
        locks         => {},
        lock_timeout  => $args->{lock_timeout} || 60,
        port          => $args->{port} || 8004,
        locker_counts => {},
    }, $class;
} #new

sub lock {
    my( $self, $key_to_lock, $locker_id, $connection ) = @_;

    print STDERR "lock request for '$locker_id' and key '$key_to_lock'\n" if $Lock::Server::DEBUG;

    $self->{locks}{$key_to_lock} ||= [];
    my $lockers = $self->{locks}{$key_to_lock};
    if( 0 < (grep { $_ eq $locker_id } @$lockers) ) {
        print STDERR "lock request error. '$locker_id' already in the lock queue\n" if $Lock::Server::DEBUG;
        print $connection "0\n";
	return;
    }

    push @$lockers, $locker_id;

    print STDERR "lock request : there are now ".scalar(@$lockers)." lockers\n" if $Lock::Server::DEBUG;

    if( @$lockers > 1 ) {
        if( (my $pid=fork)) {
            $self->{id2pid}{$locker_id} = $pid;
            $self->{locker_counts}{$locker_id}++;
	    $self->{pids}{$pid} = 1;
            print STDERR "lock request : parent process associating '$locker_id' with pid '$pid' ".scalar(@$lockers)." lockers\n" if $Lock::Server::DEBUG;
            # parent
        } else {
            # child
            $SIG{HUP} = sub {
                print STDERR "lock request : child $$ got HUP, so is now locked.\n" if $Lock::Server::DEBUG;
                print $connection "1\n";
                $connection->close;
                undef $connection;
		exit;
            };
            print STDERR "lock request : child $$ ready to wait\n" if $Lock::Server::DEBUG;
            sleep $self->{lock_timeout};
            if( $connection ) {
                print $connection "0\n";
                $connection->close;
            }
		exit;
        }
    } else {
        print STDERR "lock request : no need to invoke more processes. locking\n" if $Lock::Server::DEBUG;
        print $connection "1\n";
        $connection->close;
    }
} #lock

sub stop {
    my $self = shift;
    if( my $pid = $self->{server_pid} ) {
        $self->{error} = "Sending INT signal to lock server of pid '$pid'";
        kill 'INT', $pid;
        return 1;
    }
    $self->{error} = "No lock server running";
    return 0;
}

sub start {
    my $self = shift;
    my $listener_socket = new IO::Socket::INET(
        Listen    => 10,
        LocalPort => $self->{port},
        );
    unless( $listener_socket ) {
        $self->{error} = "Unable to open socket on port '$self->{port}' : $! $@\n";
        print STDERR "unable to start lock server : $@ $!.\n" if $Lock::Server::DEBUG;
        return 0;
    }
    $listener_socket->autoflush;
    if( my $pid = fork ) {
        # parent
        $self->{server_pid} = $pid;
        return 1;
    } else {
        # child
        $SIG{INT} = sub {
            print STDERR "lock server : got INT signal. Shutting down.\n" if $Lock::Server::DEBUG;
            $listener_socket && $listener_socket->close;
	    for my $pid (keys %{ $self->{pids} } ) {
		kill 'HUP', $pid;
	    }
            exit;
        };

        while( my $connection = $listener_socket->accept ) {
            print STDERR "lock server : incoming request\n" if $Lock::Server::DEBUG;
            my $req = <$connection>;
            print STDERR "lock server : got request '$req'\n" if $Lock::Server::DEBUG;
            if( $req =~ /^((?:UN)?LOCK) (\S+) (\S+)/i ) {
                my( $cmd, $key, $locker_id ) = ( $1, $2, $3 );
                if( lc($cmd) eq 'unlock' ) {
                    $self->unlock( $key, $locker_id, $connection );
                }
                elsif( lc($cmd) eq 'lock' ) {
                    $self->lock( $key, $locker_id, $connection );
                }
            } else {
                print STDERR "lock server : did not understand request\n" if $Lock::Server::DEBUG;
                $connection->close;
            }
        }
    } 
} #start

sub unlock {
    my( $self, $key_to_unlock, $locker_id, $connection ) = @_;
    print STDERR "unlock server ($Lock::Server::DEBUG) for key '$key_to_unlock' for locker '$locker_id'\n" if $Lock::Server::DEBUG;

    $self->{locks}{$key_to_unlock} ||= [];
    my $lockers = $self->{locks}{$key_to_unlock};

    if( $lockers->[0] eq $locker_id ) {
        shift @$lockers;
        if( 0 == --$self->{locker_counts}{$locker_id} ) {
            print STDERR "unlock : remove information about '$locker_id'\n" if $Lock::Server::DEBUG;
            delete $self->{id2pid}{$locker_id};
            delete $self->{locker_counts}{$locker_id};
        }
        print STDERR "unlocking '$locker_id'\n" if $Lock::Server::DEBUG;
        if( @$lockers ) {
            my $next_locker_id = $lockers->[0];
            my $pid = $self->{id2pid}{$next_locker_id};
            print STDERR "unlock : next locker in queue is '$next_locker_id'. Sending kill signal to its pid '$pid'\n" if $Lock::Server::DEBUG;
            kill 'HUP', $pid;
        } else {
            print STDERR "unlock : now no one waiting on a lock for key '$key_to_unlock'\n" if $Lock::Server::DEBUG;
        }
        print STDERR "unlock : done, informing connection\n" if $Lock::Server::DEBUG;
        print $connection "1\n";
        $connection->close;
    } else {
        print STDERR "unlock error : Wrong locker_id to unlock. The locker_id must be the one at the front of the queue\n" if $Lock::Server::DEBUG;
        # "Wrong locker_id to unlock. The locker_id must be the one at the front of the queue";
        print $connection "0\n";
        $connection->close;
    }
} #unlock


1;

__END__
