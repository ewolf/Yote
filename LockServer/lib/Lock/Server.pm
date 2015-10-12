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
        pids                 => {},
        id2pid               => {},
        locks                => {},
        lock_timeout         => $args->{lock_timeout} || 60,
        lock_attempt_timeout => $args->{lock_attempt_timeout} || 60,
        port                 => $args->{port} || 8004,
        locker_counts        => {},
    }, $class;
} #new

sub _log {
    my $msg = shift;
    print STDERR "\t\t$msg\n" if $Lock::Server::DEBUG;
}

sub lock {
    my( $self, $connection, $locker_id, $key_to_lock, %args ) = @_;

    _log( "lock request for '$locker_id' and key '$key_to_lock'\n" );

    $self->{locks}{$key_to_lock} ||= [];
    my $lockers = $self->{locks}{$key_to_lock};
    if( 0 < (grep { $_ eq $locker_id } @$lockers) ) {
        _log( "lock request error. '$locker_id' already in the lock queue\n" );
        print $connection "0\n";
        return;
    }

    #check for timed out lockers
    my $t = time;
    while( @$lockers && ( $t - $self->{locker_counts}{$lockers->[0]}{$key_to_lock} ) > $self->{lock_timeout} ) {
        _log( "lock '$key_to_lock' timed out for locker '$lockers->[0]'\n" );
        if( 1 == keys %{ $self->{locker_counts}{$lockers->[0]} } ) {
            delete $self->{locker_counts}{$lockers->[0]};
        } else {
            delete $self->{locker_counts}{$lockers->[0]}{$key_to_lock};
        }
        shift @$lockers;
    }

    $self->{locker_counts}{$locker_id}{$key_to_lock} = time;
    push @$lockers, $locker_id;

    _log( "lock request : there are now ".scalar(@$lockers)." lockers\n" );

    if( @$lockers > 1 ) {
        if( (my $pid=fork)) {
            $self->{id2pid}{$locker_id} = $pid;
            $self->{pids}{$pid} = 1;
            _log( "lock request : parent process associating '$locker_id' with pid '$pid' ".scalar(@$lockers)." lockers\n" );
            # parent
        } else {
            # child
            $SIG{HUP} = sub {
                _log( "lock request : child $$ got HUP, so is now locked.\n" );
                print $connection "1\n";
                $connection->close;
                undef $connection;
                exit;
            };
            _log( "lock request : child $$ ready to wait\n" );
            sleep $self->{lock_attempt_timeout};
            if( $connection ) {
                print $connection "0\n";
                $connection->close;
            }
		exit;
        }
    } else {
        _log( "lock request : no need to invoke more processes. locking\n" );
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
        _log( "unable to start lock server : $@ $!.\n" );
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
            _log( "lock server : got INT signal. Shutting down.\n" );
            $listener_socket && $listener_socket->close;
	    for my $pid (keys %{ $self->{pids} } ) {
		kill 'HUP', $pid;
	    }
            exit;
        };

        while( my $connection = $listener_socket->accept ) {
            _log( "lock server : incoming request\n" );
            my $req = <$connection>;
            _log( "lock server : got request '$req'\n" );
            if( $req =~ /^((?:UN)?LOCK) (\S+) (\S+)(.*)/i ) {
                my( $cmd, $key, $locker_id, %args ) = ( $1, $2, $3, map { $_ => 1 } split( /s+/, $4) );
                if( lc($cmd) eq 'unlock' ) {
                    $self->unlock( $connection, $locker_id, $key, %args );
                }
                elsif( lc($cmd) eq 'lock' ) {
                    $self->lock( $connection, $locker_id, $key, %args );
                }
            } else {
                _log( "lock server : did not understand request\n" );
                $connection->close;
            }
        }
    } 
} #start

sub unlock {
    my( $self, $connection, $locker_id, $key_to_unlock, %args ) = @_;
    _log( "unlock server ($Lock::Server::DEBUG) for key '$key_to_unlock' for locker '$locker_id'\n" );

    $self->{locks}{$key_to_unlock} ||= [];
    my $lockers = $self->{locks}{$key_to_unlock};

    if( $lockers->[0] eq $locker_id ) {
        shift @$lockers;
        delete $self->{locker_counts}{$locker_id}{$key_to_unlock};
        if( 0 == scalar(keys %{$self->{locker_counts}{$locker_id}}) ) {
            _log( "unlock : remove information about '$locker_id'\n" );
            delete $self->{id2pid}{$locker_id};
            delete $self->{locker_counts}{$locker_id};
        }
        _log( "unlocking '$locker_id'\n" );
        if( @$lockers ) {
            my $next_locker_id = $lockers->[0];
            my $pid = $self->{id2pid}{$next_locker_id};
            _log( "unlock : next locker in queue is '$next_locker_id'. Sending kill signal to its pid '$pid'\n" );
            kill 'HUP', $pid;
        } else {
            _log( "unlock : now no one waiting on a lock for key '$key_to_unlock'\n" );
        }
        _log( "unlock : done, informing connection\n" );
        print $connection "1\n";
        $connection->close;
    } else {
        _log( "unlock error : Wrong locker_id to unlock. The locker_id must be the one at the front of the queue\n" );
        # "Wrong locker_id to unlock. The locker_id must be the one at the front of the queue";
        print $connection "0\n";
        $connection->close;
    }
} #unlock


1;

__END__
