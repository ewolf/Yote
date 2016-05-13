package Yote::Server;

use strict;
use warnings;

no warnings 'uninitialized';
no warnings 'numeric';

use Lock::Server;
use Yote;

use bytes;
use Data::Dumper;
use IO::Socket::SSL;
use JSON;
use Time::HiRes qw(time);
use URI::Escape;

use vars qw($VERSION);

$VERSION = '1.05';

our $DEBUG = 1;

sub new {
    my( $pkg, $args ) = @_;
    my $class = ref( $pkg ) || $pkg;
    my $server = bless {
        args                 => $args || {},

        # the following are the args currently used
        yote_root_dir        => $args->{yote_root_dir},
        yote_host            => $args->{yote_host} || '127.0.0.1',
        yote_port            => $args->{yote_port} || 8881,
        pids                 => [],
        _locker              => new Lock::Server( {
            port                 => $args->{lock_port},
            host                 => $args->{lock_host} || '127.0.0.1',
            lock_attempt_timeout => $args->{lock_attempt_timeout},
            lock_timeout         => $args->{lock_timeout},
                                                  } ),
        STORE                => Yote::ServerStore->_new( { root => $args->{yote_root_dir} } ),
    }, $class;
    $server->{STORE}{_locker} = $server->{_locker};
    $server;
} #new

sub store {
    shift->{STORE};
}

sub load_options {

    my( $yote_root_dir ) = @_;

    my $confile = "$yote_root_dir/yote.conf";

    #
    # set up default options
    #
    my $options = {
        yote_root_dir        => $yote_root_dir,
        yote_host            => '127.0.0.1',
        yote_port            => 8881,
        lock_port            => 8004,
        lock_host            => '127.0.0.1',
        lock_attempt_timeout => 12,
        lock_timeout         => 10,
        use_ssl              => 0,
        SSL_cert_file        => '',
        SSL_key_file         => '',
    };

    #
    # override base defaults with those from conf file
    #
    if( -f $confile && -r $confile ) {
        # TODO - create conf with defaults and make it part of the install
        open( IN, "<$confile" ) or die "Unable to open config file $@ $!";
        while( <IN> ) {
            chomp;
            s/\#.*//;
            if( /^\s*([^=\s]+)\s*=\s*([^\s].*)\s*$/ ) {
                if( defined $options->{$1} ) {
                    $options->{$1} = $2 if defined $options->{$1};
                } else {
                    print STDERR "Warning: encountered '$1' in file. Ignoring";
                }
            }
        }
        close IN;
    } #if config file is there

    return $options;
} #load_options

sub ensure_locker {
    my $self = shift;
    # if running as the server, this will not be called. 
    # if something else is managing forking ( like the CGI )
    # this should be run to make sure the locker socket
    # opens and closes
    $SIG{INT} = sub {
        _log( "$0 got INT signal. Shutting down." );
        $self->{_locker}->stop if $self->{_locker};
        exit;
    };

    if( ! $self->{_locker}->ping(1) ) {
        $self->{_locker}->start;
    }
} #ensure_locker

sub start {
    my $self = shift;

    $self->{_locker}->start;

    my $listener_socket = $self->_create_listener_socket;
    die "Unable to open socket " unless $listener_socket;

    if( my $pid = fork ) {
        # parent
        $self->{server_pid} = $pid;
        return $pid;
    }

    # in child
    $0 = "YoteServer process";
    $self->_run_loop( $listener_socket );

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
    my $listener_socket = $self->_create_listener_socket;
    die "Unable to open socket " unless $listener_socket;
    $self->_run_loop( $listener_socket );
}

sub _create_listener_socket {
    my $self = shift;

    my $listener_socket;
    my $count = 0;

    if( $self->{use_ssl} && ( ! $self->{SSL_cert_file} || ! $self->{SSL_key_file} ) ) {
        die "Cannot start server. SSL selected but is missing filename for SSL_cert_file and/or SSL_key_file";
    }
    while( ! $listener_socket && ++$count < 10 ) {
        if( $self->{args}{use_ssl} ) {
            my $cert_file = $self->{args}{SSL_cert_file};
            my $key_file  = $self->{args}{SSL_key_file};
            if( index( $cert_file, '/' ) != 0 ) {
                $cert_file = "$self->{yote_root_dir}/$cert_file";
            }
            if( index( $key_file, '/' ) != 0 ) {
                $key_file = "$self->{yote_root_dir}/$key_file";
            }
            $listener_socket = new IO::Socket::SSL(
                Listen    => 10,
                LocalAddr => "$self->{yote_host}:$self->{yote_port}",
                SSL_cert_file => $cert_file,
                SSL_key_file => $key_file,
                );
        } else {
            $listener_socket = new IO::Socket::INET(
                Listen    => 10,
                LocalAddr => "$self->{yote_host}:$self->{yote_port}",
                );
        }
        last if $listener_socket;
        
        print STDERR "Unable to open the yote socket [$self->{yote_host}:$self->{yote_port}] ($!). Retry $count of 10\n";
        sleep 5 * $count;
    }

    unless( $listener_socket ) {
        $self->{error} = "Unable to open yote socket on port '$self->{yote_port}' : $! $@\n";
        $self->{_locker}->stop;
        _log( "unable to start yote server : $@ $!." );
        return 0;
    }

    print STDERR "Starting yote server\n";

    unless( $self->{yote_root_dir} ) {
        eval('use Yote::ConfigData');
        $self->{yote_root_dir} = $@ ? '/opt/yote' : Yote::ConfigData->config( 'yote_root' );
        undef $@;
    }

    # if this is cancelled, make sure all child procs are killed too
    $SIG{INT} = sub {
        _log( "got INT signal. Shutting down." );
        $listener_socket && $listener_socket->close;
        for my $pid ( @{ $self->{_pids} } ) {
            kill 'HUP', $pid;
        }
        $self->{_locker}->stop;
        exit;
    };

    $SIG{CHLD} = 'IGNORE';

    return $listener_socket;
} #_create_listener_socket

sub _run_loop {
    my( $self, $listener_socket ) = @_;
    while( my $connection = $listener_socket->accept ) {
        $self->_process_request( $connection );
    }
}

sub _log {
    my( $msg, $sev ) = @_;
    $sev //= 1;
    print STDERR "Yote::Server : $msg\n" if $sev <= $DEBUG;
}

sub __transform_params {
    #
    # Recursively transforms incoming parameters into values, yote objects, or non yote containers.
    # This checks to make sure that the parameters are allowed by the given token.
    # Throws execptions if the parametsr are not allowed, or if a reference that is not a hash or array
    # is encountered.
    #
    my( $self, $param, $token, $server_root ) = @_;

    if( ref( $param ) eq 'HASH' ) {
        return { map { $_ => $self->__transform_params($param->{$_}, $token, $server_root) } keys %$param };
    } 
    elsif( ref( $param ) eq 'ARRAY' ) {
        return [ map { $self->__transform_params($_, $token, $server_root) } @$param ];
    } elsif( ref( $param ) ) {
        die "Transforming Params: got weird ref '" . ref( $param ) . "'";
    }
    if( index( $param, 'v' ) == 0 ) {
        if( $server_root->_getMay( $param, $token ) ) {
            return $self->{STORE}->_xform_out( $param );
        }
        die( "Bad Req Param, server says no : $param" );
    }
    return $self->{STORE}->fetch($param); #oops!
} #__transform_params

sub _find_ids_in_data {
    my $data = shift;
    my $r = ref( $data );
    if( $r eq 'ARRAY' ) {
        return grep { $_ && index($_,'v')!=0 } map { ref( $_ ) ? _find_ids_in_data($_) : $_ } @$data;
    }
    elsif( $r eq 'HASH' ) {
        return grep { $_ && index($_,'v')!=0} map { ref( $_ ) ? _find_ids_in_data($_) : $_ } values %$data;
    }
    elsif( $r ) {
        die "_find_ids_in_data encountered a non ARRAY or HASH reference";
    }
} #_find_ids_in_data

sub _process_request {
    #
    # Reads incomming request from the socket, parses it, performs it and
    # prints the result back to the socket.
    #
    my( $self, $sock ) = @_;


    if ( my $pid = fork ) {
        # parent
        push @{$self->{_pids}},$pid;
    } else {
#      use Devel::SimpleProfiler;Devel::SimpleProfiler::start;
        my( $self, $sock ) = @_;
        #child
        $0 = "YoteServer processing request";
        $SIG{INT} = sub {
            _log( " process $$ got INT signal. Shutting down." );
            $sock->close;
            exit;
        };
        
        
        my $req = <$sock>;
        $ENV{REMOTE_HOST} = $sock->peerhost;
        my( %headers, %cookies );
        while( my $hdr = <$sock> ) {
            $hdr =~ s/\s*$//s;
            last if $hdr !~ /[a-zA-Z]/;
            my( $key, $val ) = ( $hdr =~ /^([^:]+):(.*)/ );
            $headers{$key} = $val;
        }

        for my $cookie ( split( /\s*;\s*/, $headers{Cookie} ) ) {
           $cookie =~ s/^\s*|^\s*$//g;
            my( $key, $val ) = split( /\s*=\s*/, $cookie, 2 );
            $cookies{ $key } = $val;
        }
        
        _log( "\n[$$]--> : $req" );

        # 
        # read certain length from socket ( as many bytes as content length )
        #
        my $content_length = $headers{'Content-Length'};
        my $data;
        if ( $content_length > 0 && ! eof $sock) {
            read $sock, $data, $content_length;
        }
        my( $verb, $path ) = split( /\s+/, $req );

        # escape for serving up web pages
        # the thought is that this should be able to be a stand alone webserver
        # for testing and to provide the javascript
        if ( $path =~ m!/__/! ) {
            # TODO - make sure install script makes the directories properly
            my $filename = "$self->{yote_root_dir}/html/" . substr( $path, 4 );
            if ( -e $filename ) {
                _log( "'$filename' exists" );
                my @stat = stat $filename;

                my $content_type = $filename =~ /css$/ ? 'text/css' : 'text/html';
                my @headers = (
                    "Content-Type: $content_type; charset=utf-8",
                    'Server: Yote',
                    "Content-Length: $stat[7]",
                );

                open( IN, "<$filename" );

                $sock->print( "HTTP/1.1 200 OK\n" . join ("\n", @headers). "\n\n" );

                while ( $data = <IN> ) {
                    $sock->print( $data );
                }
                close IN;
            } else {
                _log( "404 file '$filename' not found" );
                $sock->print( "HTTP/1.1 404 FILE NOT FOUND\n\n" );
            }
            $sock->close;
            exit;
        }
        

        # data has the input parmas in JSON format.
        # POST /

        if ( $verb ne 'POST' ) {
            _log( "Attempted not-suppored '$verb' request" );
            $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
            $sock->close;
        }

        $data =~ s/^p=//;
        my $out_json;
        eval {
            $out_json = $self->invoke_payload( $data );
        };
        if( $@ ) {
            _log( $@ );
            $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
            $sock->close;
            exit;
        }
        my @headers = (
            'Content-Type: text/json; charset=utf-8',
            'Server: Yote',
            'Access-Control-Allow-Headers: accept, content-type, cookie, origin, connection, cache-control',
            'Access-Control-Allow-Origin: *', #TODO - have this configurable
            'Content-Length: ' . bytes::length( $out_json ),
            );
        
        _log( "<-- 200 OK [$$] ( " . join( ",", @headers ) . " ) ( $out_json )\n" );
        $sock->print( "HTTP/1.1 200 OK\n" . join ("\n", @headers). "\n\n$out_json\n" );
        
        $sock->close;
        $self->{STORE}->stow_all;
        exit;

    } #child
} #_process_request

sub invoke_payload {
    my $self     = shift;

    _log( "jsony $_[0]" );

    my $req_data = from_json( shift );

    my( $obj_id, $token, $action, $params ) = @$req_data{ 'i', 't', 'a', 'pl' };

    _log( "\n   (params [$$])--> : ".Data::Dumper->Dump([$params]) );
    my $server_root = $self->{STORE}->fetch_server_root;
    
    my $server_root_id = $server_root->{ID};
    my $session = $server_root->_fetch_session( $token );

    unless( $obj_id eq '_' || 
            $obj_id eq $server_root_id || 
            ( $obj_id > 0 && 
              $session && 
              $server_root->_getMay( $obj_id, $session->get__token ) ) ) {
        
        # tried to do an action on an object it wasn't handed. do a 404
        die( "Bad Path" );
    }
    if( substr( $action, 0, 1 ) eq '_' ) {
        die( "Private method called" );
    }

    if ( $params && ref( $params ) ne 'ARRAY' ) {
        die( "Bad Req Param Not Array : $params" );
    }

    # now things are getting a bit more complicated. The params passed in
    # are always a list, but they may contain other containers that are not
    # yote objects. So, transform the incomming parameter list and check all
    # yote objects inside for may. Use a recursive helper function for this.

    my $in_params = $self->__transform_params( $params, $token, $server_root );

    my $store = $self->{STORE};

    my $obj = $obj_id eq '_' ? $server_root :
        $store->fetch( $obj_id );



    unless( $obj->can( $action ) ) {
        die( "Bad Req : invalid method :'$action'" );
    }

    if( $session ) {
        $obj->{SESSION} = $session;
        $obj->{SESSION}{SERVER_ROOT} = $server_root;
    }

    my(@res) = ($obj->$action( @$in_params ));
    delete $obj->{SESSION};
        
    my $out_res = $store->_xform_in( \@res, 'allow datastructures' );

    my @has = _find_ids_in_data( $out_res );
    my @mays = @has, $store->_find_ids_referenced( @has );

    my $ids_to_update;
    if ( ( $action eq 'fetch_root' || $action eq 'init_root' || $action eq 'fetch_app' )  && ( $obj_id eq '_' || $obj_id eq $server_root_id ) ) {
        # if there is a token, make it known that the token 
        # has received server root data
        $ids_to_update = [ $server_root_id, grep { $_ ne $server_root_id } @has ];
        if ( $token  ) {
            push @has, $server_root_id;
        }
    } else {
        $ids_to_update = $server_root->_updates_needed( $token, \@has );
    }
    
    my( @updates, %methods );
    for my $obj_id (@$ids_to_update) {
        my $obj = $store->fetch( $obj_id );
        my $ref = ref( $obj );
        
        my( $data );
        if ( $ref eq 'ARRAY' ) {
            $data = [ 
                map { my $d = $store->_xform_in( $_ );
                      push @mays, $d;
                      $d } 
                @$obj ];
        } elsif ( $ref eq 'HASH' ) {
            $data = {
                map { my $d = $store->_xform_in( $obj->{$_} );
                      push @mays, $d;
                      $_ => $d }
                keys %$obj };
        } else {
            my $obj_data = $obj->{DATA};
            
            $data = {
                map { my $d = $obj_data->{$_};
                      push @mays, $d;
                      $_ => $d }
                grep { $_ !~ /^_/ }
                keys %$obj_data };
            $methods{$ref} ||= $obj->_callable_methods;
        }
        push @has, $obj_id;
        my $update = {
            id    => $obj_id,
            cls   => $ref,
            data  => $data,
        };
        push @updates, $update;
    } #each obj_id to update

    $server_root->_setHasAndMay( \@has, \@mays, $token );

    my $out_json = to_json( { result  => $out_res,
                              updates => \@updates,
                              methods => \%methods,
                            } );
    return $out_json;
} #invoke_payload

# ------- END Yote::Server

package Yote::ServerStore;

use Data::RecordStore;

use Yote::Server::Obj;
use Yote::Server::Root;
use base 'Yote::ObjStore';

sub _new { #Yote::ServerStore
    my( $pkg, $args ) = @_;
    $args->{store} = "$args->{root}/DATA_STORE";
    my $self = $pkg->SUPER::_new( $args );

    # keeps track of when any object had been last updated.
    # use like $self->{OBJ_UPDATE_DB}->put_record( $obj_id, [ time ] );
    # or my( $time ) = @{ $self->{OBJ_UPDATE_DB}->get_record( $obj_id ) };
    $self->{OBJ_UPDATE_DB} = Data::RecordStore::FixedStore->open( "L", "$args->{root}/OBJ_META" );
    $self->{OBJ_UPDATE_DB}->put_record( $self->{ID}, [ Time::HiRes::time ] );
    $self;
} #_new

sub _dirty {
    my( $self, $ref, $id ) = @_;
    $self->SUPER::_dirty( $ref, $id );
    $self->{OBJ_UPDATE_DB}->ensure_entry_count( $id );
    $self->{OBJ_UPDATE_DB}->put_record( $id, [ Time::HiRes::time ] );
}

sub stow_all {
    my $self = $_[0];
    for my $obj (values %{$self->{_DIRTY}} ) {
        my $obj_id = $self->_get_id( $obj );
        $self->{OBJ_UPDATE_DB}->ensure_entry_count( $obj_id );
        $self->{OBJ_UPDATE_DB}->put_record( $obj_id, [ Time::HiRes::time ] );
    }
    $self->SUPER::stow_all;
} #stow_all

sub _stow {
    my( $self, $obj ) = @_;
    $self->SUPER::_stow( $obj );

    my $obj_id = $self->_get_id( $obj );
    $self->{OBJ_UPDATE_DB}->put_record( $obj_id, [ Time::HiRes::time ] );
}

sub _last_updated {
    my( $self, $obj_id ) = @_;
    my( $time ) = @{ $self->{OBJ_UPDATE_DB}->get_record( $obj_id ) };
    $time;
}

sub _log {
    Yote::Server::_log(shift);
}

#
# Unlike the superclass version of this, this provides an arguemnt to
# allow non-yote datastructures to be returned. The contents of those
# data structures will all recursively be xformed in.
#
sub _xform_in {
    my( $self, $val, $allow_datastructures ) = @_;

    my $r = ref $val;
    if( $r ) {
        if( $allow_datastructures) {
            # check if this is a yote object
            if( ref( $val ) eq 'ARRAY' && ! tied @$val ) {
                return [ map { ref $_ ? $self->_xform_in( $_, $allow_datastructures ) : "v$_" } @$val ];
            }
            elsif( ref( $val ) eq 'HASH' && ! tied %$val ) {
                return { map { $_ => ( ref( $val->{$_} ) ? $self->_xform_in( $val->{$_}, $allow_datastructures ) : "v$_" ) } keys %$val };
            }
        }
        return $self->_get_id( $val );
    }

    return defined $val ? "v$val" : undef;
} #_xform_in


sub _find_ids_referenced {
    my( $self, @ids ) = @_;
    my( @refd );
    for my $obj (map { $self->_xform_out( $_ ) } @ids ) {
        if( ref $obj eq 'ARRAY' ) {
            push @refd, grep { index($_,'v')!=0 } map { $self->_xform_in( $_ ) } @$obj;
        } elsif( ref $obj eq 'HASH' ) {
            push @refd, grep { index($_,'v')!=0 } map { $self->_xform_in( $_ ) } values %$obj;
        } else {
            push @refd, grep { index($_,'v')!=0 } map { $self->_xform_in( $_ ) } map { $obj->{DATA}{$_} } grep { index($_,'_') != 0 } keys %{$obj->{DATA}};
        }
    }
}

sub newobj {
    my( $self, $data, $class ) = @_;
    $class ||= 'Yote::Server::Obj';
    $class->_new( $self, $data );
} #newobj

sub fetch_server_root {
    my $self = shift;

    return $self->{SERVER_ROOT} if $self->{SERVER_ROOT};

    my $system_root = $self->fetch_root;
    my $server_root = $system_root->get_server_root;
    unless( $server_root ) {
        $server_root = Yote::Server::Root->_new( $self );
        $system_root->set_server_root( $server_root );
        $self->stow_all;
    }

    # some setup here? accounts/webapps/etc?
    # or make it simple. if the webapp has an account, then pass that account
    # with the rest of the arguments

    # then verify if the command can run on the app object with those args
    # or even : $myapp->run( 'command', @args );

    $self->{SERVER_ROOT} ||= $server_root;

    $server_root;
    
} #fetch_server_root

sub lock {
    my( $self, $key ) = @_;
    $self->{_lockerClient} ||= $self->{_locker}->client( $$ );
    $self->{_lockerClient}->lock( $key );
}

sub unlock {
    my( $self, $key ) = @_;
    $self->{_lockerClient}->unlock( $key );
}


# ------- END Yote::ServerStore



1;

__END__

=head1 NAME

Yote::Server - Serve up marshaled perl objects in javascript

=head1 DESCRIPTION

=cut





okey, this is going to have something like

my $server = new Yote::Server( { args } );

$server->start; #doesnt block
$server->run; #blocks

This is just going to serve yote objects.

_______________________

now for requests :

 they can be on the root object, specified by '_'

 root will have a method : _can_access( $obj, /%headers, methodname )
