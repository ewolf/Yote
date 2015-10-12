package Yote::Server;

use strict;
use warnings;

no warnings 'uninitialized';

use JSON;

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
    $self->{STORE} = $store;
    $self->{SERVER_ROOT} = $store->fetch_server_root;

    $SIG{HUP} = sub {
        # wait for all processes to complete, then 
        # update the root object
        while( wait() ) { }
        $self->{STORE}->stow_all;
        exit;
    }

    while( my $connection = $listener_socket->accept ) {
        $self->_process_request( $connection );
    }
} #run

sub _process_request {
    my( $self, $sock ) = @_;
    if( my $pid = fork ) {
        # parent
#        push @{$self->{pids}},$pid;
    } else {
        #child

        my $req = <$sock>;

        my $IP = $sock->peerhost;
        my %headers;
        while( my $hdr = <$sock> ) {
            $hdr =~ s/\s*$//s;
            last unless $hdr =~ /\S/;
            my( $key, $val ) = ( $hdr =~ /^([^:]+):(.*)/ );
            $headers{$key} = $val;
        }

        # validate token if any. Make sure token and ip work
        my $store = $self->{STORE};

        # 
        # read certain length from socket ( as many bytes as content length )
        #
        my $data;
        if( $content_length && ! eof $sock) {
            my $read = read $sock, $data, $content_length;
        }
        
        my( $verb, $path ) = split( /\s+/, $req );

        # data has the input parmas in JSON format.
        # GET /obj/action/params
        # PUT /obj/action  (params in PUT data)

        # root is /_/

        my $params;
        if( $verb eq 'GET' ) {
            my( $obj_id, $action, @params ) = split( '/', $path );
            $params = \@params;
        } elsif( $verb eq 'PUT' ) {
            my( $obj_id, $action ) = split( '/', $path );
            $params = from_json( $data );
        }
        
        my $token = $headers{TOKEN};
        unless( $obj_id eq '_' || ( $self->_valid_token( $token, $IP ) && $self->_canhas( $obj_id, $token ) ) ) {
            # tried to do an action on an object it wasn't handed. do a 404
            $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
            $sock->close;
            return;
        }

        if( $params && ref( $params ) ne 'ARRAY' ) {
            $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
            $sock->close;
            return;
        }

        my( @in_params );
        for my $param (@$params) {
            unless( $self->_canhas( $obj_id, $token ) ) {
                $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
                $sock->close;
                return;
            }
            push @in_params, $store->_xform_out( $param );
        }


        my $server_root = $self->{SERVER_ROOT};

        my $obj = $obj_id eq '_' ? $server_root :
            $store->fetch( $obj_id );
        
        my $res = $obj->$action( @in_params );

        my( @out_res );
        if( $res ) {
            my $val = $store->_xform_in( $res );
            $self->_willhas( $val, $token ) ;
            push @out_res, $val;
        }
        my $out_res = to_json( \@out_res );

        my @headers = (
            'Content-Type: text/json; charset=utf-8',
            'Server: Yote',
            'Access-Control-Allow-Headers: accept, content-type, cookie, oriogin, connection, cache-control',
            );

        $sock->print( "HTTP/1.1 200 OK\n" . join ("\n", @headers). "\n\n$out_res" );

        $sock->close;

        $self->{STORE}->stow_all;

        exit;
    } #child
} # _process_request

package Yote::ServerStore;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote;
use Yote::ObjStore;

use parent 'Yote::ObjStore';

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
        $server_root = new Yote::ServerRoot;
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
use Yote::Obj;

use parent 'Yote::Obj';

#
# what things will the server root provide?
# logins? apps?
#
# fetch_app? It's just an object.
#

sub fetch_app {
    my( $self, $app_name, @args ) = @_;

    my $apps = $self->get_apps( {} );
    my $app = $apps->{$app_name};
    unless( $app ) {
        eval("require $app_name");
        return undef if $@;

        $app = $app_name->new;
        $apps->{$app_name} = $app;
    }

    if( $app->can_access( @args ) ) {
        return $app;
    }
    undef;
} #fetch_app

package Yote::ServerApp;


use strict;
use warnings;
no warnings 'uninitialized';

use Yote;
use Yote::Obj;

use parent 'Yote::Obj';

sub can_access {
    1; # override to allow control of app access. Args will be passed in
}

package Yote::ServerObj;

use Yote;
use Yote::Obj;

use parent 'Yote::Obj';

my $Yote::ServerObj::PKG2METHS = {};
sub __discover_methods {
    my $pkg = shift;
    my $meths = $Yote::ServerObj::PKG2METHS->{$pkg};
    if( $meths ) {
        return $meths;
    }

    no strict 'refs';
    my @m = grep { $_ !~ /::/ } keys %{"${pkg}\::"};

    if( $pkg eq 'Yote::ServerObj' ) {
        return \@m;
    }
    
    for my $class ( @{"${pkg}\::ISA" } ) {
        next if $class eq 'Yote::ServerObj' || $class eq 'Yote::Obj';
        my $pm = __discover_methods( $class );
        push @m, @$pm;
    }

    my $base_meths = __discover_methods( 'Yote::ServerObj' );
    my( %base ) = map { $_ => 1 } @$base_meths;

    $meths = [ grep { ! $base{$_} } @m ];
    $Yote::ServerObj::PKG2METHS->{$pkg} = $meths;
    
    $meths;
} #__discover_methods

# when sending objects across, the format is like
# id : { data : { }, methods : [] }
# the methods exclude all the methods of Yote::Obj
sub _callable_methods {
    my $self = shift;
    my $meth = $self->{_methods};
    unless( $meth ) {
        my $pkg = ref( $self );
        $meth = __discover_methods( $pkg );
    }
    $meth
} # _callable_methods

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
