package Lock::Server;

=head1 NAME

    Lock::Server - Light-weight RESTful socket based resource locking manager.

=head1 DESCRIPTION

    This creates a socket server that handles lock and 
    unlock requests. The lock requests only return once a lock is
    obtained or a timeout has occurred. A lock may only be locked
    for a specific amount of time before the lock is timed out.

    The protocol used is RESTFUL HTTP though the helper class wraps
    that. It uses the GET verb with the following paths :

     * CHECK/key - returns 1 if the key in question is currently locked 
                   returns 0 if not

     * LOCK/key/requester - returns lock expire time or 0 
                            if there was an error

     * UNLOCK/key/requester - returns 1 if the unlock went as expected, 
                              0 otherwise

     * VERIFY/key/requester - returns 1 if the key is locked to the
                              requester and did not time out and 0 
                              otherwise.

    This does not do deadlock detection, relying on the timeouts to 
    prevent the system from getting in a hopelessly tangled state.
    Care should be taken, as with any resource locking system, with
    the use of Lock::Server. Adjust the timeouts for what makes sense
    with the system you are designing. The lock requests return with the
    time that the lock will expire.

=head1 SYNPOSIS

    use Lock::Server;
    use Lock::Server::Client;

    my $lockServer = new Lock::Server( {
       lock_timeout         => 10, #seconds. default is 3
       lock_attempt_timeout => 12, #seconds. default is 4
       port                 => 888, #default is 8004
       host                 => 'localhost', #default 127.0.0.1
    } );

    if( my $childPid = $lockServer->start ) {
        print "Lock server started in child thread $childPid\n";
    }

    my $optional_args = { reconnect_attempts => 3, time_between_attempts => 1 };
    my $lockClient_A = $lockServer->client( "CLIENT_A", $optional_args );
    my $lockClient_B = 
        new Lock::Server::Client( "CLIENT_B", 'localhost', 888, $optional_args );

    if( $lockClient_A->lock( "KEYA" ) ) {
       print "Lock Successfull for locker A and KEYA\n";
    } else {
       print "Could not obtain lock in 12 seconds.\n";
    }

    # KEYA for LockerI times out after 10 seconds.
    # Lock Client B waits until it can obtain the lock
    if( $lockClient_B->lock( "KEYA" ) ) {
       print "Lock Successfull for Client B lock 'KEYA'\n";
    } else {
       print "Could not obtain lock in 12 seconds.\n";
    }

    # KEYA for LockerII is now freed. The next locker
    # attempting to lock KEYA will then obtain the lock.
    if( $lockClientB->unlock( "KEYA" ) ) {
       print "Unlock Successfull\n";
    }

    if( $lockServer->stop ) {
        print "Lock server shut down.\n";
    }

=head1 METHODS

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use Data::Dumper;

use IO::Socket::INET;

use vars qw($VERSION);

$VERSION = '1.6';


$Lock::Server::DEBUG = 0;

=head2 Lock::Server::new( $args )

 Creates a new lock server for the given optional arguments.
 
 Arguments are :
   * port - port to serve on. Defaults to 8004
   * lock_timeout - low long should a lock last in seconds
   * lock_attempt_timeout - how long should a requester
                            wait for a lock in seconds

=cut
sub new {
    my( $pkg, $args ) = @_;
    my $class = ref( $pkg ) || $pkg;
    bless {
        lock_timeout         => $args->{lock_timeout} || 3,
        lock_attempt_timeout => $args->{lock_attempt_timeout} || 4,
        host                 => $args->{host} || '127.0.0.1',
        port                 => $args->{port} || 8004,
        _pids                => {},
        _id2pid              => {},
        _locks               => {},
        _locker_counts       => {},
        attempts => $args->{reconnect_attemps} || 10,
        time_between_attempts => $args->{time_between_attempts} || 5,

    }, $class;
} #new


=head2 client( lockername )

    Returns a client with the given name that can send lock and unlock requests for keys.

=cut
sub client {
    my( $self, $name, $args ) = @_;
    Lock::Server::Client->new( $name, $self->{host}, $self->{port}, $args );
}

=head2 stop

    Kills the lock server, breaking off any connections that are waiting for a lock.

=cut
sub stop {
    my $self = shift;

    for my $pid (keys %{$self->{_id2pid}}) {
        _log( "Killing child proc $pid" );
        kill 'INT', $pid;
    }
    
    if( my $pid = $self->{server_pid} ) {
        $self->{error} = "Sending INT signal to lock server of pid '$pid'";
        _log( "Killing lock server proc $pid" );
        kill 'INT', $pid;
        return 1;
    }
    $self->{error} = "No lock server running";
    return 0;
}

=head2 start

    Starts the lock server in a child process, opening up a 
    tcpip socket and returning the child pid or 0 if there
    was an error.

=cut
sub start {
    my $self = shift;
    my $sock = $self->_create_listener_socket;
    die "Unable to open lockserver socket " unless $sock;

    if( my $pid = fork ) {
        # parent
        $self->{server_pid} = $pid;
        return $pid;
    }

    # child process
    $0 = "LockServer";
    $self->_run_loop( $sock );

} #start

=head2 run

    Runs the lock server.

=cut
sub run {
    my $self = shift;
    my $sock = $self->_create_listener_socket;
    die "Unable to open lockserver socket " unless $sock;
    $self->_run_loop( $sock );
} #run

sub _create_listener_socket {
    my $self = shift;


    my( $listener_socket, $count );

    my $st = time;
    
    until( $listener_socket || $count++ > $self->{attempts} ) {
        $listener_socket = new IO::Socket::INET(
            Listen    => 10,
            LocalAddr => "$self->{host}:$self->{port}",
            );
        last if $listener_socket;
        print STDERR "Unable to open the lock server socket. Retry $count of 10\n";
        sleep $count*$self->{time_between_attempts} unless $listener_socket;
    }
    unless( $listener_socket ) {

        $self->{error} = "Unable to open socket on port '$self->{port}' : $! $@\n";
        _log( "unable to start lock server : $@ $!." );
        return 0;
    }

    # if this is cancelled, make sure all child procs are killed too
    $SIG{INT} = sub {
        _log( "lock server : got INT signal. Shutting down." );
        $listener_socket && $listener_socket->close;
        kill 'HUP', keys %{ $self->{_pids} };
        exit;
    };

    return $listener_socket;
} #_create_listener_socket

sub _run_loop {
    my( $self, $listener_socket ) = @_;
    while( my $connection = $listener_socket->accept ) {
        my $req = <$connection>; 
        chomp $req;
        _log( "lock server : incoming request : '$req'" );

        # could have headers, but ignore those. Find \n\n
        while( my $data = <$connection> ) {
            chomp $data;
            last unless $data =~ /\S/;
        }

        my( $cmd, $key, $locker_id ) = ( $req =~ m!^GET /([^/]+)/([^/]+)/?([^/]+)?! );

        if( $cmd eq 'CHECK' ) {
            $self->_check( $connection, $key );
        }
        elsif( $cmd eq 'LOCK' ) {
            $self->_lock( $connection, $key, $locker_id );
        } elsif( $cmd eq 'UNLOCK' ) {
            $self->_unlock( $connection, $key, $locker_id );
        } elsif( $cmd eq 'VERIFY' ) {
            $self->_verify( $connection, $key, $locker_id );
        } else {
            _log( "lock server : did not understand command '$cmd'" );
            $connection->close;
        }
    }
} #_run_loop

sub _check {
    my( $self, $connection, $key_to_check ) = @_;
    _log( "locker server check for key '$key_to_check'" );

    $self->{_locks}{$key_to_check} ||= [];
    my $lockers = $self->{_locks}{$key_to_check};

    
    #check for timed out lockers
    my $t = time;
    while( @$lockers && $t > $self->{_locker_counts}{$lockers->[0]}{$key_to_check} ) {
        _log( "lock server _check : '$key_to_check' timed out for locker '$lockers->[0]'" );
        if( 1 == keys %{ $self->{_locker_counts}{$lockers->[0]} } ) {
            delete $self->{_locker_counts}{$lockers->[0]};
        } else {
            delete $self->{_locker_counts}{$lockers->[0]}{$key_to_check};
        }
        shift @$lockers;
    }


    if( @$lockers ) {
        print $connection "1\n";
    } else {
        print $connection "0\n";
    }
    $connection->close;
}

sub _log {
    my $msg = shift;
    print STDERR "Lock::Server : $msg\n" if $Lock::Server::DEBUG;
}

sub _lock {
    my( $self, $connection, $key_to_lock, $locker_id ) = @_;

    _log( "lock request :  for '$locker_id' and key '$key_to_lock'" );

    $self->{_locks}{$key_to_lock} ||= [];
    my $lockers = $self->{_locks}{$key_to_lock};
    #check for timed out lockers
    my $t = time;

    while( @$lockers && $t > $self->{_locker_counts}{$lockers->[0]}{$key_to_lock} ) {
        _log( "lock '$key_to_lock' timed out for locker '$lockers->[0]'" );
        if( 1 == keys %{ $self->{_locker_counts}{$lockers->[0]} } ) {
            delete $self->{_locker_counts}{$lockers->[0]};
        } else {
            delete $self->{_locker_counts}{$lockers->[0]}{$key_to_lock};
        }
        shift @$lockers;
    }

    if( 0 < (grep { $_ eq $locker_id } @$lockers) ) {
        _log( "lock request error. '$locker_id' already in the lock queue" );
        print $connection "0\n";
        return;
    }

    # store when this times out 
    my $timeout_time = time + $self->{lock_timeout};
    $self->{_locker_counts}{$locker_id}{$key_to_lock} = $timeout_time;
    push @$lockers, $locker_id;

    _log( "lock request : there are now ".scalar(@$lockers)." lockers" );
    if( @$lockers > 1 ) {
        if( (my $pid=fork)) {
            $self->{_id2pid}{$locker_id} = $pid;
            $self->{_pids}{$pid} = 1;
            _log( "lock request : parent process associating '$locker_id' with pid '$pid' ".scalar(@$lockers)." lockers" );
            # parent
        } else {
#            use Devel::SimpleProfiler;Devel::SimpleProfiler::start;
            $0 = "LockServer processing request";
            $SIG{HUP} = $SIG{INT} = sub {
                _log( "lock request : child $$ got HUP, so is now locked." );
                $connection->print( "$timeout_time\n" );
                $connection->close;
                exit;
            };
            _log( "lock request : child $$ ready to wait" );
            sleep $self->{lock_attempt_timeout};
            _log( "lock request failed : child $$ timed out" );
            print $connection "0\n";
            $connection->close;
            exit;
        }
    } else {
        _log( "lock request : no need to invoke more processes. locking" );
        print $connection "$timeout_time\n";
        $connection->close;
    }
} #_lock

sub _unlock {
    my( $self, $connection, $key_to_unlock, $locker_id ) = @_;
    _log( "unlock request : key '$key_to_unlock' for locker '$locker_id'" );

    $self->{_locks}{$key_to_unlock} ||= [];
    my $lockers = $self->{_locks}{$key_to_unlock};

    if( $lockers->[0] eq $locker_id ) {
        shift @$lockers;
        delete $self->{_locker_counts}{$locker_id}{$key_to_unlock};
        if( 0 == scalar(keys %{$self->{_locker_counts}{$locker_id}}) ) {
            _log( "unlock : remove information about '$locker_id'" );
            delete $self->{_id2pid}{$locker_id};
            delete $self->{_locker_counts}{$locker_id};
        }
        _log( "unlocking '$locker_id'" );
        if( @$lockers ) {
            my $next_locker_id = $lockers->[0];
            my $pid = $self->{_id2pid}{$next_locker_id};
            _log( "unlock : next locker in queue is '$next_locker_id'. Sending kill signal to its pid '$pid'" );
            kill 'HUP', $pid;
        } else {
            _log( "unlock : now no one waiting on a lock for key '$key_to_unlock'" );
        }
        _log( "unlock : done, informing connection" );
        print $connection "1\n";
        $connection->close;
    } else {
        _log( "unlock error : Wrong locker_id to unlock for unlock for locker '$locker_id' and key '$key_to_unlock'. The locker_id must be the one at the front of the queue" );
        # "Wrong locker_id to unlock. The locker_id must be the one at the front of the queue";
        print $connection "0\n";
        $connection->close;
    }
} #_unlock

sub _verify {
    my( $self, $connection, $key_to_check, $locker_id ) = @_;

    _log( "verify : locker server check for key '$key_to_check' for locker '$locker_id'" );

    $self->{_locks}{$key_to_check} ||= [];
    my $lockers = $self->{_locks}{$key_to_check};

    #check for timed out lockers
    my $t = time;
    while( @$lockers && $t > $self->{_locker_counts}{$lockers->[0]}{$key_to_check} ) {
        _log( "verify:  '$key_to_check' timed out for locker '$lockers->[0]'" );
        if( 1 == keys %{ $self->{_locker_counts}{$lockers->[0]} } ) {
            delete $self->{_locker_counts}{$lockers->[0]};
        } else {
            delete $self->{_locker_counts}{$lockers->[0]}{$key_to_check};
        }
        shift @$lockers;
    }

    if( $lockers->[0] eq $locker_id ) {
        print $connection "1\n";
    } else {
        print $connection "0\n";
    }
    $connection->close;
}



=head1 Helper package

=head2 NAME

    Lock::Server::Client - client for locking server.

=head2 DESCRIPTION

    Sends request to a Lock::Server to lock, unlock and check locks.

=head2 METHODS

=cut
package Lock::Server::Client;

use strict;
use warnings;
no warnings 'uninitialized';

use IO::Socket::INET;

use vars qw($VERSION);

$VERSION = '1.6';


=head3 new( lockername, host, port )

    Creates a client object with the given name for the host and port.

=cut
sub new {
    my( $pkg, $lockerName, $host, $port, $args ) = @_;
    die "Must supply locker name" unless $lockerName;

    $host ||= '127.0.0.1';
    $port ||= '8004';

    my $class = ref( $pkg ) || $pkg;
    bless {
        host => $host,
        port => $port,
        name => $lockerName,
        attempts => $args->{reconnect_attemps} || 3,
        time_between_attempts => $args->{time_between_attempts} || 3,
    }, $class;
} #new 

sub _get_sock {
    my $self = shift;
    
    # try a few times, then give up
    my( $sock, $count );
    until( $sock || $count++ > $self->{attempts} ) {
        $sock = new IO::Socket::INET( "$self->{host}:$self->{port}" );
        sleep $self->{time_between_attempts}*($count) unless $sock;
    }
    die "Could not connect : $@" unless $sock;
    binmode $sock, ':utf8';
    $sock;
}

=head3 isLocked( key )

    Returns true if the key is locked by anyone.

=cut
sub isLocked {
    my( $self, $key ) = @_;
	my $sock = $self->_get_sock;

    $sock->print( "GET /CHECK/$key\n\n" );
    my $resp = <$sock>;
    $sock->close;
    chomp $resp;
    $resp;
}

=head3 lockedByMe( key )

    Returns true if the key is locked by this client or 
    anyone with the name of this client. The name was given in the constructor.

=cut
sub lockedByMe {
    my( $self, $key ) = @_;
	my $sock = $self->_get_sock;

    $sock->print( "GET /VERIFY/$key/$self->{name}\n\n" );
    my $resp = <$sock>;
    $sock->close;
    chomp $resp;
    $resp;
}

=head3 lock( key )

    Attempt to get the lock for the given key. Returns true if the lock
    was obtained.

=cut
sub lock {
    my( $self, $key ) = @_;
	my $sock = $self->_get_sock;

    $sock->print( "GET /LOCK/$key/$self->{name}\n\n" );
    my $resp = <$sock>;
    $sock->close;
    chomp $resp;
    $resp;
}

=head3 unlock( key )

    Attempt to get unlock the given key. Returns true if the
    key was locked to this client ( or someting with the same name ).

=cut
sub unlock {
    my( $self, $key ) = @_;
	my $sock = $self->_get_sock;
    $sock->print( "GET /UNLOCK/$key/$self->{name}\n\n" );
    my $resp = <$sock>;
    $sock->close;
    chomp $resp;
    $resp;
}

1;


__END__

=head1 AUTHOR

       Eric Wolf        coyocanid@gmail.com

=head1 COPYRIGHT AND LICENSE

       Copyright (c) 2015 Eric Wolf. All rights reserved.  This program is free software; you can redistribute it and/or modify it
       under the same terms as Perl itself.

=head1 VERSION

       Version 1.6  (Mar 9, 2016))

=cut
