package Yote::Server;

use strict;
use warnings;

no warnings 'uninitialized';

sub new {
    my( $pkg, $args ) = @_;
    my $class = ref( $pkg ) || $pkg;
    bless {
        args                 => $args,
        host                 => $args->{host} || '127.0.0.1',
        port                 => $args->{port} || 8881,
        pids                 => [],
    }, $class;
} #new

sub start {
    my $self = shift;
    if( my $pid = fork ) {
        # parent
        $self->{server_pid} = $pid;
        return $pid;
    }
    
    # child process
    $self->run;

} #start

sub stop {
    my $self = shift;
    if( my $pid = $self->{server_pid} ) {
        $self->{error} = "Sending INT signal to lock server of pid '$pid'";
        kill 'INT', $pid;
        return 1;
    }
    $self->{error} = "No Yote server running";
    return 0;
}


=head2 run

    Runs the lock server.

=cut
sub run {
    my $self = shift;


    my $listener_socket = new IO::Socket::INET(
        Listen    => 10,
        LocalAddr => "$self->{host}:$self->{port}",
        );
    unless( $listener_socket ) {
        $self->{error} = "Unable to open socket on port '$self->{port}' : $! $@\n";
        _log( "unable to start lock server : $@ $!." );
        return 0;
    }

    # if this is cancelled, make sure all child procs are killed too
    $SIG{INT} = sub {
        _log( "lock server : got INT signal. Shutting down." );
        $listener_socket && $listener_socket->close;
        for my $pid (keys %{ $self->{_pids} } ) {
            kill 'HUP', $pid;
        }
        exit;
    };

    eval('use Yote::ConfigData');
    my $yote_root_dir = $@ ? '/opt/yote' : Yote::ConfigData->config( 'yote_root' );

    my $store = Yote::ServerStore->_new( { store => "$yote_root_dir/DATA_STORE" } );
    $self->{SERVER_ROOT} = $store->fetch_server_root;

    $SIG{HUP} = sub {
        # wait for all processes to complete, then 
        # update the root object
    }

    while( my $connection = $listener_socket->accept ) {
        $self->_process_request( $connection );
    }
} #run

sub _process_request {
    my( $self, $sock ) = @_;
    if( my $pid = fork ) {
        # parent
        push @{$self->{pids}},$pid;
    } else {
        #child

        my $req = <$socket>;

        my %headers;
        while( my $hdr = <$sock> ) {
            $hdr =~ s/\s*$//s;
            last unless $hdr =~ /\S/;
            my( $key, $val ) = ( $hdr =~ /^([^:]+):(.*)/ );
            $headers{$key} = $val;
        }
        $sock->close;

        # 
        # read certain length from socket ( as many bytes as content length )
        #
        my $data;
        if( $content_length && ! eof $sock) {
            my $read = read $sock, $data, $content_length;
        }
        $sock->close;
        
        my( $verb, $path ) = split( /\s+/, $req );

        # data has the input parmas in JSON format.
        # GET /obj/action/params
        # PUT /obj/action  (params in PUT data)

        # root is /_/

        my $params;
        if( $verb eq 'GET' ) {
            my( $obj, $action, @params ) = split( '/', $path );
            $params = \@params;
        } elsif( $verb eq 'PUT' ) {
            my( $obj, $action ) = split( '/', $path );
            $params = $data;
        }
        
        

    } #child
}

package Yote::ServerStore;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote;
use Yote::ObjStore;

use parent Yote::ObjStore;

sub newobj {
    my( $self, $data, $class ) = @_;
    $class ||= 'Yote::ServerObj';
    $class->_new( $self, $data );
} #newobj

sub fetch_server_root {
    my $self = shift;

    my $system_root = $self->fetch_root;
    
    my $server_root = $system_root->get_server_root;
    unless( $server_root ) {
        $server_root = $self->newobj;
        $system_root->set_server_root( $server_root );
    }

    # some setup here? accounts/webapps/etc?
    # or make it simple. if the webapp has an account, then pass that account
    # with the rest of the arguments

    # verify the token - ip match in the server root object
    
    # then verify if the command can run on the app object with those args
    # or even : $myapp->run( 'command', @args );

    $server_root;
    
} #fetch_server_root

package Yote::ServerRoot;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote;
use Yote::ObjStore;


1;

__END__


okey, this is going to have something like

my $server = new Yote::Server( { args } );

$server->start; #doesnt block
$server->run; #blocks

This is just going to serve yote objects.

_______________________

now for requests :

 they can be on the root object, specified by '_'

 root will have a method : can_access( $obj, /%headers, methodname )
