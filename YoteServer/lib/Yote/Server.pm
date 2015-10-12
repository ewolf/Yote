package Yote::Server;

use strict;
use warnings;

no warnings 'uninitialized';
no warnings 'numeric';

use Lock::Server;
use Yote;

use JSON;
use URI::Escape;

my $DEBUG = 0;

sub new {
    my( $pkg, $args ) = @_;
    my $class = ref( $pkg ) || $pkg;
    bless {
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
} #new

sub start {
    my $self = shift;

    $self->{STORE}->{_locker} = $self->{_locker};
    $self->{_locker}->start;

    $self->{SERVER_ROOT} = $self->{STORE}->fetch_server_root;


    if( my $pid = fork ) {
        # parent
        $self->{server_pid} = $pid;
        return $pid;
    }
    $0 = "YoteServer process";
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
        LocalAddr => "$self->{yote_host}:$self->{yote_port}",
        );
    unless( $listener_socket ) {
        $self->{error} = "Unable to open socket on port '$self->{yote_port}' : $! $@\n";
        $self->{_locker}->stop;
        _log( "unable to start lock server : $@ $!." );
        return 0;
    }


    unless( $self->{yote_root_dir} ) {
        eval('use Yote::ConfigData');
        $self->{yote_root_dir} = $@ ? '/opt/yote' : Yote::ConfigData->config( 'yote_root' );
        undef $@;
    }

    # if this is cancelled, make sure all child procs are killed too
    $SIG{INT} = sub {
        _log( "Yote server : got INT signal. Shutting down." );
        $listener_socket && $listener_socket->close;
        for my $pid ( @{ $self->{_pids} } ) {
            kill 'HUP', $pid;
        }
        $self->{_locker}->stop;
        exit;
    };

    while( my $connection = $listener_socket->accept ) {
        $self->_process_request( $connection );
    }

} #run

sub _log {
    print STDERR shift . "\n" if $DEBUG;
    
}

sub _process_request {
    my( $self, $sock ) = @_;
    if( my $pid = fork ) {
        # parent
        push @{$self->{_pids}},$pid;
    } else {
        #child
        $0 = "YoteServer processing request";
        $SIG{INT} = sub {
            _log( "Yote server process $$ : got INT signal. Shutting down." );
            $sock->close;
            exit;
        };


        my $req = <$sock>;
        $ENV{REMOTE_HOST} = $sock->peerhost;
        my %headers;
        while( my $hdr = <$sock> ) {
            $hdr =~ s/\s*$//s;
#            print STDERR Data::Dumper->Dump([$hdr,"H"]);
            last if $hdr !~ /[a-zA-Z]/;
            my( $key, $val ) = ( $hdr =~ /^([^:]+):(.*)/ );
            $headers{$key} = $val;
        }

        my $store = $self->{STORE};

        $store->{_lockerClient} = $store->{_locker}->client( $$ );

        print STDERR "\n\n----\nREQ : $req\n";

#        print STDERR Data::Dumper->Dump([$req,\%headers,"HHH"]);
        # 
        # read certain length from socket ( as many bytes as content length )
        #
        my $content_length = $headers{'Content-Length'};
        my $data;
        if( $content_length > 0 && ! eof $sock) {
            read $sock, $data, $content_length;
        }
        my( $verb, $path ) = split( /\s+/, $req );


        # escape for serving up web pages
        # the thought is that this should be able to be a stand alone webserver
        # for testing and to provide the javascript
#        print STDERR Data::Dumper->Dump([$path,"CHEK $verb"]);
        if( $path =~ m!/__/! ) {
            # TODO - make sure install script makes the directories properly
            my $filename = "$self->{yote_root_dir}/html/" . substr( $path, 4 );
            _log( "Request for '$filename'" );
            if( -e $filename ) {
                _log( "'$filename' exists" );
                my @stat = stat $filename;

                my @headers = (
                    'Content-Type: text/html; charset=utf-8',
                    'Server: Yote',
                    "Content-Length: $stat[7]",
                    );


                open( IN, "<$filename" );
                my $data;

                $sock->print( "HTTP/1.1 200 OK\n" . join ("\n", @headers). "\n\n" );

                while( $data = <IN> ) {
                    $sock->print( $data );
                }
                close IN;
            } else {
                _log( "404 file '$filename' not found" );
                $sock->print( "HTTP/1.1 404 FILE NOT FOUND\n\n" );
            }
            $sock->close;
            return;
        }
        

        # data has the input parmas in JSON format.
        # GET /obj/action/params
        # POST /obj/action  (params in POST data)

        # root is /_/

#        print STDERR Data::Dumper->Dump([$data,"DDD"]);

        my( $obj_id, $token, $action, $params );
        if( $verb eq 'GET' ) {
            ( $obj_id, $token, $action, my @params ) = split( '/', substr( $path, 1 ) );
            $params = [ map { URI::Escape::uri_unescape($_) } @params ];
            
        } elsif( $verb eq 'POST' ) {
            ( $obj_id, $token, $action ) = split( '/', substr( $path, 1 ) );
            $params = [ map { URI::Escape::uri_unescape($_) } 
                        map { s/^[^=]+=//; s/\+/ /gs; $_; } 
                        split ( '&', $data ) ];
        }

        if( substr( $action, 0, 1 ) eq '_' ) {
            print STDERR "Bad action (underscore) : $action\n";
            _log( "Bad Action : '$action'" );
            $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
            $sock->close;
            exit;
        }

        # check to see if it is just simple webserving
        
        my $server_root = $self->{SERVER_ROOT};
        my $server_root_id = $server_root->{ID};

        unless( $obj_id eq '_' || 
                $obj_id eq $server_root_id || 
                ( $obj_id > 0 && 
                  $server_root->_valid_token( $token, $ENV{REMOTE_HOST} ) && 
                  $server_root->_getMay( $obj_id, $token ) ) ) {

            # tried to do an action on an object it wasn't handed. do a 404
            print STDERR "Bad Path : $path\n";
            _log( "Bad Req : '$path'" );
            $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
            $sock->close;
            exit;
        }

        if( $params && ref( $params ) ne 'ARRAY' ) {
            print STDERR "Bad Req Param Not Array : $params\n";
            $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
            _log( "Bad Req : params:'$params'" );
            $sock->close;
            exit;
        }

        my( @in_params );
        for my $param (@$params) {
            unless( $server_root->_getMay( $param, $token ) ) {
                print STDERR "Bad Req Param, server says no : $param\n";
                _log( "Bad Req : param:'$param'" );
                $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
                $sock->close;
                exit;
            }
            push @in_params, $store->_xform_out( $param );
        }
#        print STDERR Data::Dumper->Dump([\@in_params,$action," in params"]);


        my $obj = $obj_id eq '_' ? $server_root :
            $store->fetch( $obj_id );

        unless( $obj->can( $action ) ) {
            print STDERR "Bad Req Action : $action\n";
            _log( "Bad Req : invalid method :'$action'" );
            $sock->print( "HTTP/1.1 400 BAD REQUEST\n\n" );
            $sock->close;
            exit;
        }

        
        my( @res );
        eval {
            if( $action eq 'fetch' && $obj == $server_root ) {
                # fetch is a special action that can return any 
                # object in the system. It must check the token
                # to see if that particular object is allowed/available
                # to the caller
                push( @in_params, $token );
            }
            (@res) = ($obj->$action( @in_params ));
        };

        if( $@ ) {
            print STDERR "Internal error $@\n";
            _log( "INTERNAL SERVER ERROR '$@'" );
            $sock->print( "HTTP/1.1 500 INTERNAL SERVER ERROR\n\n" );
            $sock->close;
            return;
        }

        my( @out_res );

        for my $res (@res) {
            my $val = $store->_xform_in( $res );
            # mark that it may and does have the token
            $server_root->_setMay( $val, $token );
            push @out_res, $val;
        }
        my $ids_to_update;
        if( $action eq 'fetch_root' && ( $obj_id eq '_' || $obj_id eq $server_root_id ) ) {
            # if there is a token, make it known that the token 
            # has received server root data
            $ids_to_update = [ $server_root_id ];
            if( $token > 1  ) {
                unless( $store->_last_updated( $server_root_id ) ) {
                    $store->{OBJ_UPDATE_DB}->put_record( $server_root_id, [ time ] );
                }
                $server_root->_setHas( $server_root_id, $token );
            }
        } else {
            $ids_to_update = $server_root->_updates_needed( $token, \@out_res );
        }

        for my $res (@out_res) {
            $server_root->_setHas( $res, $token );
        }
        
        my( @updates, %methods );
        for my $obj_id (@$ids_to_update) {
            my $obj = $store->fetch( $obj_id );
            my $ref = ref( $obj );

            my( $data, $meths );
            if( $ref eq 'ARRAY' ) {
                $data = [ 
                    map { my $d = $store->_xform_in( $_ );
                          $server_root->_setMay( $d, $token );
                          $d } 
                    @$obj ];
            } elsif( $ref eq 'HASH' ) {
                $data = {
                    map { my $d = $store->_xform_in( $obj->{$_} );
                          $server_root->_setMay( $d, $token );
                          $_ => $d } 
                    keys %$obj };
                
            } else {
                my $obj_data = $obj->{DATA};

                $data = {
                    map { my $d = $store->_xform_in( $obj_data->{$_} );
                          $server_root->_setMay( $d, $token );
                          $_ => $d } 
                    grep { $_ !~ /^_/ }
                    keys %$obj_data };
                $methods{$ref} ||= $obj->_callable_methods;
            }
            $server_root->_setHas( $obj_id, $token );
            my $update = {
                id    => $obj_id,
                cls   => $ref,
                data  => $data,
            };
            push @updates, $update;
        } #each obj_id to update
        
        my $out_res = to_json( { result  => \@out_res,
                                 updates => \@updates,
                                 methods => \%methods,
                               } );
        my @headers = (
            'Content-Type: text/json; charset=utf-8',
            'Server: Yote',
            'Access-Control-Allow-Headers: accept, content-type, cookie, origin, connection, cache-control',
            'Access-Control-Allow-Origin: *', #TODO - have this configurable
            'Content-Length: ' . length( $out_res ),
            );
        print STDERR "RET : 200 OK ( " . join( ",", @headers ) . " ) ( $out_res )\n";
        _log( "200 OK ( " . join( ",", @headers ) . " ) ( $out_res )" );
        $sock->print( "HTTP/1.1 200 OK\n" . join ("\n", @headers). "\n\n$out_res\n" );

        $sock->close;
        $self->{STORE}->stow_all;
        exit;
    } #child
} # _process_request

# ------- END Yote::Server

package Yote::ServerStore;

use strict;
use warnings;
no warnings 'uninitialized';

use DB::DataStore;

use base 'Yote::ObjStore';

sub _new { #Yote::ServerStore
    my( $pkg, $args ) = @_;
    $args->{store} = "$args->{root}/DATA_STORE";
    my $self = $pkg->SUPER::_new( $args );

    # keeps track of when any object had been last updated.
    # use like $self->{OBJ_UPDATE_DB}->put_record( $obj_id, [ time ] );
    # or my( $time ) = @{ $self->{OBJ_UPDATE_DB}->get_record( $obj_id ) };
    $self->{OBJ_UPDATE_DB} = DB::DataStore::FixedStore->open( "L", "$args->{root}/OBJ_META" );
    $self;
} #_new

sub stow_all {
    my $self = $_[0];
    for my $obj (values %{$self->{_DIRTY}} ) {
        my $obj_id = $self->_get_id( $obj );
        print STDERR "Noting obj update '$obj_id' at ".time."\n";
        $self->{OBJ_UPDATE_DB}->put_record( $obj_id, [ time ] );
    }
    $self->SUPER::stow_all;       
} #stow_all

sub _stow {
    my( $self, $obj ) = @_;
    $self->SUPER::_stow( $obj );

    my $obj_id = $self->_get_id( $obj );
    print STDERR "Noting obj update '$obj_id' at ".time."\n";
    $self->{OBJ_UPDATE_DB}->put_record( $obj_id, [ time ] );
}

sub _last_updated {
    my( $self, $obj_id ) = @_;
    my( $time ) = @{ $self->{OBJ_UPDATE_DB}->get_record( $obj_id ) };
    $time;
}

sub _log {
    Yote::Server::_log(shift);
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
        $server_root = Yote::ServerRoot->_new( $self );
        $system_root->set_server_root( $server_root );
        $self->stow_all;
    }

    # some setup here? accounts/webapps/etc?
    # or make it simple. if the webapp has an account, then pass that account
    # with the rest of the arguments

    # verify the token - ip match in the server root object
    
    # then verify if the command can run on the app object with those args
    # or even : $myapp->run( 'command', @args );


    $server_root;
    
} #fetch_server_root

sub lock {
    my( $self, $key ) = @_;
    $self->{_lockerClient}->lock( $key );
}

sub unlock {
    my( $self, $key ) = @_;
    $self->{_lockerClient}->unlock( $key );
}


# ------- END Yote::ServerStore

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

    if( $pkg eq 'Yote::ServerObj' ) { #the base, presumably
        return [ grep { $_ !~ /^(_|[gs]et_|can|AUTOLOAD|BEGIN|isa|PKG2METHS|ISA$)/ } @m ];
    }
    
    for my $class ( @{"${pkg}\::ISA" } ) {
        next if $class eq 'Yote::ServerObj' || $class eq 'Yote::Obj';
        my $pm = __discover_methods( $class );
        push @m, @$pm;
    }

    my $base_meths = __discover_methods( 'Yote::ServerObj' );
    my( %base ) = map { $_ => 1 } 'AUTOLOAD', @$base_meths;

    $meths = [ grep { $_ !~ /^(_|[gs]et_|can|AUTOLOAD|BEGIN|isa|PKG2METHS|ISA$)/ && ! $base{$_} } @m ];
    $Yote::ServerObj::PKG2METHS->{$pkg} = $meths;
    
    $meths;
} #__discover_methods

# when sending objects across, the format is like
# id : { data : { }, methods : [] }
# the methods exclude all the methods of Yote::Obj
sub _callable_methods {
    my $self = shift;
    my $pkg = ref( $self );
    __discover_methods( $pkg );
} # _callable_methods

sub get {
    my( $self, $fld, $default ) = @_;
    if( index( $fld, '_' ) == 0 ) {
        die "Cannot get private field $fld";
    }
    $self->_get( $fld, $default );
} #get


sub _get {
    my( $self, $fld, $default ) = @_;
    if( ! defined( $self->{DATA}{$fld} ) && defined($default) ) {
        if( ref( $default ) ) {
            $self->{STORE}->_dirty( $default, $self->{STORE}->_get_id( $default ) );
        }
        $self->{STORE}->_dirty( $self, $self->{ID} );
        $self->{DATA}{$fld} = $self->{STORE}->_xform_in( $default );
    }
    $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
} #_get


sub set {
    my( $self, $fld, $val ) = @_;
    if( index( $fld, '_' ) == 0 ) {
        die "Cannot set private field";
    }
    my $inval = $self->{STORE}->_xform_in( $val );
    $self->{STORE}->_dirty( $self, $self->{ID} ) if $self->{DATA}{$fld} ne $inval;
    $self->{DATA}{$fld} = $inval;
    
    $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
} #set


# ------- END Yote::ServerObj

package Yote::ServerRoot;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::ServerObj';

sub _init {
    my $self = shift;
    $self->set__token2ip({});
    $self->set__doesHave_Token2objs({});
    $self->set__mayHave_Token2objs({});
    $self->set__apps({});
    $self->set__appOnOff({});
    $self->set__token_timeslots([]);
    $self->set__token_timeslots_metadata([]);
    $self->set__token_mutex([]);
}

sub _valid_token {
    my( $self, $token, $ip ) = @_;
    my $slots = $self->get__token_timeslots();
    for( my $i=0; $i<@$slots; $i++ ) {
        if( $slots->[$i]{$token} eq $ip ) {
            if( $i < $#$slots ) {
                # refresh its time
                $self->{STORE}->lock( 'token_mutex' );
                $slots->[0]{ $token } = $ip;
                $self->{STORE}->unlock( 'token_mutex' );
            }
            return 1;
        }
    }
    0;
}

sub _token2objs {
    my( $self, $tok, $flav ) = @_;
    my $item = "_${flav}_Token2objs";
    $self->{STORE}->lock( $item );
    my $token2objs = $self->_get( $item );
    my $objs = $token2objs->{$tok};
    unless( $objs ) {
        $objs = {};
        $token2objs->{$tok} = $objs;
    }
#    print STDERR Data::Dumper->Dump([$objs,"LOAD $flav T2O"]);

    $objs;
}

sub _resetHasAndMay {
    my( $self, $token ) = @_;
    $self->{STORE}->lock( "_canToken2objs" );
    for ( qw( doesHave mayHave ) ) {
        my $item = "_${_}Token2objs";
        $self->{STORE}->lock( $item );
        my $token2objs = $self->_get( $item );
        delete $token2objs->{ $token };
        $self->{STORE}->unlock( $item );
    }
}

sub _setHas {
    my( $self, $id, $token ) = @_;
    return 1 if index( $id, 'v' ) == 0 || $token eq '_';
    my $obj_data = $self->_token2objs( $token, 'doesHave' );
    print STDERR "ADDING '$id' to HAS\n";
    $obj_data->{$id} = time;
    $self->{STORE}->unlock( "_hasToken2objs" );
}

sub _getMay {
    my( $self, $id, $token ) = @_;
    return 1 if index( $id, 'v' ) == 0;
    return 0 if $token eq '_';
    my $obj_data = $self->_token2objs( $token, 'mayHave' );
    $self->{STORE}->lock( $obj_data );
    my $has = $obj_data->{$id};
    print STDERR "$id " . ( $has ? " MAY " : " MAY NOT" ). "\n";
    $self->{STORE}->unlock( "_canToken2objs" );
    $has;
}

sub _setMay {
    my( $self, $id, $token ) = @_;
    return 1 if index( $id, 'v' ) == 0 || $token eq '_';
    my $obj_data = $self->_token2objs( $token, 'mayHave');
    $obj_data->{$id} = time - 1;
    print STDERR "ADDING '$id' to MAY\n";
    $self->{STORE}->unlock( "_canToken2objs" );
}


sub _updates_needed {
    my( $self, $token, $outRes ) = @_;
    return [] if $token eq '_';
    my $obj_data = $self->_token2objs( $token, 'doesHave' );
    my $store = $self->{STORE};
    my( @updates );
    for my $obj_id (@$outRes, keys %$obj_data ) {
        next if index( $obj_id, 'v' ) == 0;
        my $last_update_sent = $obj_data->{$obj_id};
        my $last_updated = $store->_last_updated( $obj_id );
        if( $last_update_sent < $last_updated || $last_updated == 0 ) {
            unless( $last_updated ) {
                $store->{OBJ_UPDATE_DB}->put_record( $obj_id, [ time ] );
            }
            push @updates, $obj_id;
        }
    }
    $self->{STORE}->unlock( "_hasToken2objs" );
    \@updates;
} #_updates_needed


sub create_token {
    my $self = shift;

    my $randpart = int( rand( 1_000_000_000 ) ); #TODO - find max this can be for long int
    my $ip = $ENV{REMOTE_HOST};
    
    # make the token boat. tokens last at least 10 mins, so quantize
    # 10 minutes via time 10 min = 600 seconds = 600
    # or easy, so that 1000 seconds ( ~ 16 mins )
    # todo - make some sort of quantize function here
    my $timechunk = int( time / 100 );
    my $timeslot  = 7 + $timechunk;

    $self->{STORE}->lock( 'token_mutex' );

    my $slots     = $self->get__token_timeslots();
    my $slot_data = $self->get__token_timeslots_metadata();

    #
    # check if the token is already used ( very unlikely ) and remove expired slots
    #
    my $to_remove = 0;
    for( my $i=0; $i<@$slot_data; $i++ ) {
        # remove slots that are too old
        if( $slot_data->[ $i ] < $timechunk ) {
            $to_remove++;
        } elsif( $slots->[ $i ]{ $randpart } ) {
            # if this produces the same rand number lots of times in a row
            # something serious is wrong, so a stack overflow error is the least
            # of worries
            print STDERR Data::Dumper->Dump(["BLA"]);die "REMOVEME";
            return $self->create_token;
        }
    }
    for( my $i=0; $i<$to_remove; $i++ ) {
        shift @$slots;
        shift @$slot_data;
    }

    #
    # Find out which boat this should be on. Create a new boat if necessary.
    #
    my $found = 0;
    for( my $i=0; $i<@$slot_data; $i++ ) {
        if( $slot_data->[ $i ] == $timeslot ) {
            $slots->[ $i ]{ $randpart } = $ip;
            $found = 1;
            last;
        }
    }
    unless( $found ) {
        push @$slot_data, $timeslot;
        push @$slots, { $randpart => $ip };
    }

    $self->{STORE}->unlock( 'token_mutex' );

    return $randpart;

} #create_token

#
# what things will the server root provide?
# logins? apps?
#
# fetch_app? It's just an object.
#

sub fetch_app {
    my( $self, $app_name, @args ) = @_;

    my $apps = $self->get__apps;
    my $app  = $apps->{$app_name};
    unless( $app ) {
        eval("require $app_name");
        if( $@ ) {
            # TODO - have/use a good logging system with clarity and stuff
            # warnings, errors, etc
            $self->{STORE}->_log( "App '$app_name' not found" );
            return undef;
        }
        $self->{STORE}->_log( "Loading app '$app_name'" );
        $app = $app_name->new;
        $apps->{$app_name} = $app;
    }
    my $appIsOn = $self->get__appOnOff->{$app_name};
    unless( $appIsOn ) {
        $self->{STORE}->_log( "App '$app_name' not found" );
        return undef;
    }
    $app->can_access( @args ) ? $app : undef;
} #fetch_app

sub fetch_root {
    return shift;
}

sub fetch {
    my( $self, $id, $token ) = @_;
    if( $self->_getMay( $id, $token ) && ! ref( $id ) ) {
        return $self->{STORE}->fetch( $id );
    }
    die "Invalid id '$id'";
}

# ------- END Yote::ServerRoot

package Yote::ServerApp;


use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::ServerObj';

sub can_access {
    1;
}

# ------- END Yote::ServerApp

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
