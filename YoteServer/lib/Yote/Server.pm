package Yote::Server;

use strict;
use warnings;

no warnings 'uninitialized';

use Lock::Server;
use Yote;

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

    my $locker = new Lock::Server;
    $locker->start;

    # if this is cancelled, make sure all child procs are killed too
    $SIG{INT} = sub {
        _log( "lock server : got INT signal. Shutting down." );
        $listener_socket && $listener_socket->close;
        for my $pid (keys %{ $self->{_pids} } ) {
            kill 'HUP', $pid;
        }
        $locker->stop;
        exit;
    };



    eval('use Yote::ConfigData');
    my $yote_root_dir = $@ ? '/opt/yote' : Yote::ConfigData->config( 'yote_root' );

    my $store = Yote::ServerStore->_new( { root => "$yote_root_dir" } );
    $store->{_locker} = $locker;

    $self->{STORE} = $store;
    $self->{SERVER_ROOT} = $store->fetch_server_root;

    $SIG{HUP} = sub {
        # wait for all processes to complete, then 
        # update the root object
        while( wait() ) { }
        $self->{STORE}->stow_all;
        exit;
    };

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

        $store->{_lockerClient} = $store->{_locker}->client( $$ );


        # 
        # read certain length from socket ( as many bytes as content length )
        #
        my $content_length;
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
        my( $obj_id, $action );
        if( $verb eq 'GET' ) {
            ( $obj_id, $action, my @params ) = split( '/', $path );
            $params = \@params;
        } elsif( $verb eq 'PUT' ) {
            ( $obj_id, $action ) = split( '/', $path );
            $params = from_json( $data );
        }
        
        my $server_root = $self->{SERVER_ROOT};

        my $token = $headers{TOKEN};
        unless( $obj_id eq '_' || ( $self->_valid_token( $token, $IP ) && $server_root->_canhas( $obj_id, $token ) ) ) {
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
            unless( $server_root->_canhas( $obj_id, $token ) ) {
                $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
                $sock->close;
                return;
            }
            push @in_params, $store->_xform_out( $param );
        }



        my $obj = $obj_id eq '_' ? $server_root :
            $store->fetch( $obj_id );
        
        my $res;
        eval {
            $res = $obj->$action( @in_params );
        };

        if( $@ ) {
            print STDERR Data::Dumper->Dump(["ERROR '$@'",$obj,$action,\@in_params]);
            $sock->print( "HTTP/1.1 500 INTERNAL SERVER ERROR\n\n" );
            $sock->close;
            return;
        }

        my( @out_res );
        if( $res ) {
            my $val = $store->_xform_in( $res );
            $server_root->_willhas( $val, $token ) ;
            $server_root->_has( $val, $token ) ;
            push @out_res, $val;
        }
        my $ids_to_update = $store->_updates_needed( $token );
        
        my( @updates, %methods );
        for my $obj_id (@$ids_to_update) {
            my $obj = $store->fetch( $obj_id );
            my $ref = ref( $obj );

            my( $data, $meths );
            if( $ref eq 'ARRAY' ) {
                $data = [ 
                    map { my $d = $store->_xform_in( $_ );
                          $store->_willhas( $d, $token ); 
                          $d } 
                    @$obj ];
            } elsif( $ref eq 'HASH' ) {
                $data = {
                    map { my $d = $store->_xform_in( $obj->{$_} );
                          $store->_willhas( $d, $token ); 
                          $_ => $d } 
                    keys %$obj };
                
            } else {
                my $obj_data = $obj->{DATA};
                
                $data = {
                    map { my $d = $store->_xform_in( $obj_data->{$_} );
                          $store->_willhas( $d, $token ); 
                          $_ => $d } 
                    grep { $_ !~ /^_/ }
                    keys %$obj_data };

                $methods{$ref} ||= $obj->_callable_methods;
            }
            my $update = {
                id    => $obj_id,
                class => $ref,
                data  => $data,
            };
            push @updates, $update;
        }
        

        my $out_res = to_json( { result  => \@out_res,
                                 updates => \@updates,
                                 methods => \%methods,
                               } );

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

use DB::DataStore;

use base 'Yote::ObjStore';

sub _new {
    my( $pkg, $args ) = @_;
    $args->{store} = "$args->{root}/DATA_STORE";
    my $self = $pkg->SUPER::_new( $args );
    
    # keeps track of when any object had been last updated.
    # use like $self->{OBJ_UPDATE_DB}->put_record( $obj_id, [ time ] );
    # or my( $time ) = @{ $self->{OBJ_UPDATE_DB}->get_record( $obj_id ) };
    
    $self->{OBJ_UPDATE_DB} = DB::DataStore::FixedStore->open( "L", "$args->{root}/OBJ_META" );
    $self;
}

sub _stow {
    my( $self, $obj ) = @_;
    $self->SUPER::_stow( $obj );

    my $obj_id = $self->_get_id( $obj );
    $self->{OBJ_UPDATE_DB}->put_record( $obj_id, [ time ] );
}

sub _last_updated {
    my( $self, $obj_id ) = @_;
    my( $time ) = @{ $self->{OBJ_UPDATE_DB}->get_record( $obj_id ) };
    $time;
}


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



package Yote::ServerObj;

use base 'Yote::Obj';

$Yote::ServerObj::PKG2METHS = {};
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

    $meths = [ grep { $_ !~ /^_/ && ! $base{$_} } @m ];
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

sub get {
    my( $self, $fld, $default ) = @_;
    if( ! defined( $self->{DATA}{$fld} ) && defined($default) ) {
        if( ref( $default ) ) {
            $self->{STORE}->_dirty( $default, $self->{STORE}->_get_id( $default ) );
        }
        $self->{STORE}->_dirty( $self, $self->{ID} );
        $self->{DATA}{$fld} = $self->{STORE}->_xform_in( $default );
    }
    $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
}

sub set {
    my( $self, $fld, $val ) = @_;
    my $inval = $self->{STORE}->_xform_in( $val );
    $self->{STORE}->_dirty( $self, $self->{ID} ) if $self->{DATA}{$fld} ne $inval;
    $self->{DATA}{$fld} = $inval;
    
    $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
}

sub lock {
    my( $self, $obj ) = @_;
    my $obj_id = $self->{STORE}->_get_id( $obj || $self );
    $self->{STORE}{_lockerClient}->lock( $obj_id );
}

sub unlock {
    my( $self, $obj ) = @_;
    my $obj_id = $self->{STORE}->_get_id( $obj || $self );
    $self->{STORE}{_lockerClient}->unlock( $obj_id );
}

package Yote::ServerApp;


use strict;
use warnings;
no warnings 'uninitialized';

use Yote;

use base 'Yote::ServerObj';


package Yote::ServerRoot;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::ServerObj';

sub _init {
    my $self = shift;
    $self->set_hasToken2objs({});
    $self->set_canToken2objs({});
    $self->set_apps({});
}

sub _token2objs {
    my( $self, $tok, $flav ) = @_;
    my $token2objs = $self->get( "${flav}Token2objs" );
    $self->lock( $token2objs );
    my $objs = $token2objs->{$tok};
    unless( $objs ) {
        $objs = {};
        $token2objs->{$tok} = $objs;
    }
    $self->unlock( $token2objs );
    $objs;
}

sub _has {
    my( $self, $id, $token ) = @_;
    return if $id < 1;
    my $obj_data = _token2objs( $token, 'has' );
    $obj_data->{$id} = time - 1;
    $self->unlock( $obj_data );
}

sub _resethas {
    my( $self, $token ) = @_;
    for my ( qw( has can ) ) {
        my $token2objs = $self->get( "${_}Toekn2objs" );
        $self->lock( $token2objs );
        delete $token2objs->{ $token };
        $self->unlock( $token2objs );
    }
}

sub _canhas {
    my( $self, $id, $token, 'can' ) = @_;
    return 1 if $id < 1;
    my $obj_data = _token2objs( $token );
    $self->lock( $obj_data );
    my $has = $obj_data->{$id};
    $self->unlock( $obj_data );
    $has;
}

sub _willhas {
    my( $self, $id, $token, 'can' ) = @_;
    return if $id < 1;
    my $obj_data = _token2objs( $token );
    $obj_data->{$id} = time - 1;
    $self->unlock( $obj_data );
}


sub _updates_needed {
    my( $self, $token ) = @_;
    my $obj_data = _token2objs( $token, 'has' );
    my $store = $self->{STORE};

    my( @updates );
    for my $obj_id (keys %$obj_data ) {
        my $last_update_sent = $obj_data->{$obj_id};
        my $last_updated = $store->_last_updated( $obj_id );
        if( $last_update_sent < $last_updated ) {
            push @updates, $obj_id;
        }
    }
    $self->unlock( $obj_data );
    \@updates;
} #_updates_needed

#
# what things will the server root provide?
# logins? apps?
#
# fetch_app? It's just an object.
#

sub fetch_app {
    my( $self, $app_name, @args ) = @_;

    my $apps = $self->get_apps;
    my $app  = $apps->{$app_name};
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
