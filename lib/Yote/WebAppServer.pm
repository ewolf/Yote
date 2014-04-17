package Yote::WebAppServer;

use forks;
use forks::shared;

use strict;
use warnings;
no warnings 'uninitialized';

use Data::Dumper;
use MIME::Base64;
use IO::Handle;
use IO::Socket;
use JSON;
use POSIX qw(strftime);

use Yote::AppRoot;
use Yote::ConfigData;
use Yote::FileHelper;
use Yote::ObjManager;
use Yote::ObjProvider;
use Yote::IO::Mailer;

use vars qw($VERSION);

$VERSION = '0.2';

# %oid2lockdata stores object id to a string containg locking process id, and last saved time.
#   The resolution scheme is for the requesting process to unlock (and possibly save) objects that it has locked that are being requested
#    by an other thread that has locked an item this thread is waiting on.
# 
my( %oid2lockdata );
share( %oid2lockdata );


# ------------------------------------------------------------------------------------------
#      * INIT METHODS *
# ------------------------------------------------------------------------------------------

sub new {
    my $pkg = shift;
    my $class = ref( $pkg ) || $pkg;
    return bless {}, $class;
}

# ------------------------------------------------------------------------------------------
#      * PUBLIC METHODS *
# ------------------------------------------------------------------------------------------


sub accesslog {
    my( $msg ) = @_;
    my $t = strftime "%Y-%m-%d %H:%M:%S", gmtime;
    print $Yote::WebAppServer::ACCESS "$t : $msg\n";
}


sub errlog {
    my( $msg ) = @_;
    my $t = strftime "%Y-%m-%d %H:%M:%S", gmtime;
    print $Yote::WebAppServer::ERR "$t : $msg\n";
}

sub iolog {
    my( $msg ) = @_;
    my $t = strftime "%Y-%m-%d %H:%M:%S", gmtime;
    print $Yote::WebAppServer::IO "$t : $msg\n";
}

sub lock_object {
    my( $self, $obj_id, $ref ) = @_;
    # LOCKED in this case means already locked by this thread
    if( $obj_id eq Yote::ObjProvider::first_id() || $self->{ LOCKED }{ $obj_id } ) {
	return $ref;
    }

    while( 1 ) {
	my( @locked );
	{
	    lock( %oid2lockdata );
	    my $lockdata = $oid2lockdata{ $obj_id };

	    if( ! $lockdata ) {
		$oid2lockdata{ $obj_id } = "$$|";
		$self->{ LOCKED }{ $obj_id } = 1;
		return $ref;
	    }
	    my( $locking_pid, $dirty_time, @pids_waiting_for_this_object ) = split( /\|/, $lockdata );

	    my( %waiters ) = map { $_ => 1 } @pids_waiting_for_this_object;

	    if( ! $locking_pid ) {
		delete $waiters{$$}; #remove this from any waiting list
		$oid2lockdata{ $obj_id } = join( '|', $$, $dirty_time, keys %waiters );
		$self->{ LOCKED }{ $obj_id } = 1;
		if( $dirty_time &&  $Yote::ObjProvider::LAST_LOAD_TIME->{ $obj_id } && $Yote::ObjProvider::LAST_LOAD_TIME->{ $obj_id } <= $dirty_time ) {
		    # means the object is dirty and should be reloaded
		    return;
		}
		return $ref;
	    } # not locking pid
	    
	    # lock data indicates this obj is locked by an other pid. 
	    # Check to make sure that pid isn't waiting on what we have locked, for that is deadlock
	    my @locked_ids = keys %{ $self->{LOCKED} || {} };
	    for my $locked_oid ( @locked_ids ) {
		# check if the process that has obj_id locked is waiting on any of the locked objects that are had.
		if( $waiters{ $locking_pid } ) {
		    # if this object is dirty then 
		    if( Yote::ObjProvider::__is_dirty( $locked_oid ) ) {
			$self->unlock_objects( keys %{ $self->{LOCKED} } );
			Yote::ObjProvider::flush( map { Yote::ObjProvider::__is_dirty( $_ ) } keys %{ $self->{LOCKED} } );
			die "__DEADLOCK__";
		    }
		}
		else { # the object is clean so can be unlocked from this thread
		    push @locked, $locked_oid;
		}
	    } #each locked oid

	    if( $waiters{$$} ) {
		# if I am already in the waiters, I'm already in @pids_waiting_for_this_object
		$oid2lockdata{ $obj_id } = join( '|', $locking_pid, $dirty_time, @pids_waiting_for_this_object );
	    } 
	    else {
		# add me to @pids_waiting_for_this_object
		$oid2lockdata{ $obj_id } = join( '|', $locking_pid, $dirty_time, $$, @pids_waiting_for_this_object );
	    }
	    
	    unless( @locked ) {
		lock( %oid2lockdata );
		cond_wait( %oid2lockdata );
	    }
	} # scope for locked var

	if( @locked ) {
	    $self->unlock_objects( @locked );
	    lock( %oid2lockdata );
	    cond_wait( %oid2lockdata );
	}
    } #while loop
} #lock_object


sub shutdown {
    my $self = shift;
    accesslog( "Shutting down yote server" );
    Yote::ObjProvider::start_transaction();
    Yote::ObjProvider::stow_all();
    Yote::ObjProvider::commit_transaction();
    accesslog(  "Killing threads" );
    $self->__stop_threads();
    accesslog( "Shut down server thread" );
} #shutdown

sub start_server {
    my( $self, @args ) = @_;
    my $args = scalar(@args) == 1 ? $args[0] : { @args };

    $self->{ args } = $args;
    $self->{ args }{ webroot } ||= $self->{ args }{ yote_root } . '/html';
    $self->{ args }{ upload }  ||= $self->{ args }{ webroot }   . '/upload';
    $self->{ args }{ log_dir } ||= $self->{ args }{ yote_root } . '/log';
    $self->{ args }{ port }    ||= 80;
    $self->{ args }{ threads } ||= 10;

    # make sure the filehelper knows where the data directory is
    $Yote::WebAppServer::LOG_DIR       = $self->{args}{log_dir};
    $Yote::WebAppServer::FILE_DIR      = $self->{args}{data_dir} . '/holding';
    $Yote::WebAppServer::WEB_DIR       = $self->{args}{webroot};
    $Yote::WebAppServer::UPLOAD_DIR    = $self->{args}{webroot}. '/uploads';
    mkdir( $Yote::WebAppServer::FILE_DIR );
    mkdir( $Yote::WebAppServer::WEB_DIR );
    mkdir( $Yote::WebAppServer::UPLOAD_DIR );
    mkdir( $Yote::WebAppServer::LOG_DIR );

    open( $Yote::WebAppServer::IO,      '>>', "$Yote::WebAppServer::LOG_DIR/io.log" )
		      && $Yote::WebAppServer::IO->autoflush;
    open( $Yote::WebAppServer::ACCESS,  '>>', "$Yote::WebAppServer::LOG_DIR/access.log" )
		      && $Yote::WebAppServer::ACCESS->autoflush;
    open( $Yote::WebAppServer::ERR,     '>>', "$Yote::WebAppServer::LOG_DIR/error.log" )
		      && $Yote::WebAppServer::ERR->autoflush;

    $self->{ init_args } = $args;
    Yote::ObjProvider::init( %$args );
    Yote::IO::Mailer::init( %$args );

    # fork out for three starting threads
    #   - one a multi forking server (parent class)
    #   - one for a cron daemon inside of Yote. (PENDING)
    #   - and the parent thread an event loop.

    my $root = Yote::YoteRoot::fetch_root();
    Yote::ObjProvider::stow_all();
    # check for default account and set its password from the config.
    $root->_update_master_root( $args->{ root_account }, $args->{ root_password } );


    # make sure the filehelper knows where the data directory is

    # update @INC library list
    my $paths = $root->get__application_lib_directories([]);
    push @INC, Yote::ConfigData->config( 'yote_root' ), @$paths;

    until( $self->{lsn} ) {
	$self->{lsn} = new IO::Socket::INET(Listen => 10, LocalPort => $self->{args}{port});
	unless( $self->{lsn} ) {
	    if( $! =~ /Address already in use/i ) {
		print STDERR "Address already in use. Retrying.\n";
		sleep( 5 );
	    } else {
		die $!;
	    }
	}
    }

    print STDERR "Connected\n";
    
    $self->{ threads } = {};
    
    Yote::ObjProvider::attach_server( $self );
    for( 1 .. $self->{args}{threads} ) {
	$self->__start_server_thread;
    } #creating threads

    Yote::ObjProvider::flush_all_volatile();
    $self->__unlock_all();

    while( 1 ) {
	sleep( 5 );
	my $threads = $self->{ threads };
	for my $thread ( values %$threads ) {
	    if( $thread->is_joinable() ) {
		delete $threads->{ $thread->tid() };
		$thread->join();
	    }
	}
	while( scalar( keys %$threads ) < $self->{ args }{ threads } ) {
	    $self->__start_server_thread;
	}
	eval { 
	    my $cron = $root->_cron();
	    my $cron_entries = $cron->entries();
	    Yote::ObjProvider::flush_all_volatile();
	    $self->__unlock_all();
	    for my $entry (@$cron_entries) {
		threads->new( sub {
		    $cron->_mark_done( $entry );
		    print STDERR "Starting cron thread " . threads->tid() . "\n";
		    my $script = $entry->get_script();
		    print STDERR "EVAL $script\n";
		    eval "$script";
		    print STDERR "Done EVAL\n";
		    if( $@ ) {
			print STDERR "Error in Cron : $@ $!\n";
		    } 
		    $self->__check_locked_for_dirty();
		    Yote::ObjProvider::start_transaction();
		    Yote::ObjProvider::stow_all();
		    Yote::ObjProvider::flush_all_volatile();
		    Yote::ObjProvider::commit_transaction();
		    $self->__unlock_all();
		    print STDERR "Done cron thread " . threads->tid() . "\n";
			      } ); #done with cron entry thread
	    } #each cron entry
	};
	print STDERR "ERROR IN CRON : $@ $!" if $@;
    } #endless loop

    __stop_threads();

   Yote::ObjProvider::disconnect();

} #start_server

sub unlock_objects {
    my( $self, @objs ) = @_;
    @objs = grep { $self->{ LOCKED }{ $_ } } @objs;
    if( @objs ) {
	lock( %oid2lockdata );
	for my $obj_id ( @objs ) {
	    $oid2lockdata{ $obj_id } =~ s/^([^\|]+)//; 
#	print STDERR "[$$ ".time()."] UNLOCKED $obj_id : $oid2lockdata{ $obj_id }\n";
	    delete $self->{ LOCKED }{ $obj_id };
	}
	cond_signal( %oid2lockdata );
    }
} #unlock_objects

# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

sub __check_locked_for_dirty {
    my( $self  ) = @_;
    my( @dirty_oids ) = grep { Yote::ObjProvider::__is_dirty( $_ ) } keys %{ $self->{LOCKED} || {} };
    if( @dirty_oids ) {
	lock( %oid2lockdata );
	my $t = time();
	for my $dirty_oid ( @dirty_oids ) {
	    my( $locking_pid, $last_dirty_time, @pids_waiting_for_this_object ) = split( /\|/, $oid2lockdata{ $dirty_oid } );
	    $oid2lockdata{ $dirty_oid } = join( '|', $locking_pid, $t, @pids_waiting_for_this_object );
	}
    } #if dirty
} #__check_locked_for_dirty

sub _do404 {
    my $self = shift;
    print "HTTP/1.0 404 NOT FOUND\015\012Content-Type: text/html\n\nERROR : 404\n";
}



sub __stop_threads {
    my $self = shift;
    $self->{watchdog_thread}->kill if $self->{watchdog_thread} && $self->{watchdog_thread}->is_running;
    for my $thread (values %{$self->{threads}}) {
	$thread->join if $thread && $thread->is_joinable;
	$thread->kill if $thread && $thread->is_running;
    }
} #__stop_threads

sub __start_server_thread {
    my $self = shift;

    my $new_thread = threads->new(
	sub {
	    Yote::ObjProvider::init( %{$self->{ init_args } } );
	    print STDERR "Starting server thread " . threads->tid() . "\n";
	    $SIG{PIPE} = sub { # a client disconnected before receiving a response
		print STDERR "Thread $$ got sig pipe. Exiting\n";
		$self->{lsn}->close() if $self->{lsn};
		threads->exit()
	    };
	    unless( $self->{lsn} ) {
		threads->exit();
	    }
	    
	    open( $Yote::WebAppServer::IO,      '>>', "$Yote::WebAppServer::LOG_DIR/io.log" ) 
		&& $Yote::WebAppServer::IO->autoflush;
	    open( $Yote::WebAppServer::ACCESS,  '>>', "$Yote::WebAppServer::LOG_DIR/access.log" )
		&& $Yote::WebAppServer::ACCESS->autoflush;
	    open( $Yote::WebAppServer::ERR,     '>>', "$Yote::WebAppServer::LOG_DIR/error.log" )
		&& $Yote::WebAppServer::ERR->autoflush;
	    
	    while( my $fh = $self->{lsn}->accept ) {
		eval {
		    $ENV{ REMOTE_ADDR } = $fh->peerhost;
		    $self->__process_http_request( $fh );
		};
		if( $@ ) {
		    $self->{lsn}->close() if $self->{lsn};
		    last;
		}
		$fh->close();
	    } #main loop
	} ); #new thread
    $self->{ threads }{ $new_thread->tid() } = $new_thread;
    
} #__start_server_thread

sub __process_command {
    my( $self, $command ) = @_;
    my $resp;

    eval {
        my $obj_id = $command->{oi};
        my $app_id = $command->{ai};

        my $app         = Yote::ObjProvider::fetch( $app_id ) || Yote::YoteRoot::fetch_root();

        my $data        = __translate_data( from_json( MIME::Base64::decode( $command->{d} ) )->{d} );

#	iolog( "  * CMD IN $$ : " . Data::Dumper->Dump( [ $command ] ) );

#	iolog( "  * DATA IN $$ : " . Data::Dumper->Dump( [ $data ] ) );

        my $login       = $app->token_login( $command->{t}, undef, $command->{e} );
	my $guest_token = $command->{gt};

	$command->{e}{GUEST_TOKEN} = $guest_token;

	# security check
	unless( Yote::ObjManager::allows_access( $obj_id, $app, $login, $guest_token ) ) {
	    accesslog( "INVALID ACCCESS ATTEMPT for $obj_id from $command->{e}{ REMOTE_ADDR }" );
	    die "Access Error";
	}

        my $app_object = Yote::ObjProvider::fetch( $obj_id ) || $app;
        my $action     = $command->{a};

	die "Access Error" if $action =~ /^([gs]et|add_(once_)?to_|remove_(all_)?from)_/; # set may not be called directly on an object.
        my $account;
        if( $login ) {
	    die "Access Error" if $login->get__is_disabled();
            $account = $app->__get_account( $login );
	    die "Access Error" if $app->get_requires_validation() && ! $login->get__is_validated();
	    die "Access Error" if $account->get__is_disabled() || $login->get__is_disabled();
	    $account->set_login( $login ); # security measure to make sure login can't be overridden by a subclass of account
	    $login->add_once_to__accounts( $account );
        }
        my $ret = $app_object->$action( $data, $account, $command->{e} );
	
	# prepare the response object
	$resp = { r =>  __obj_to_response( $ret, $login, $guest_token ) };

	# check if there are object updates that should be included. This means objects that have changed on the server side
	# since the last time the client was updated
	my $dirty_delta = Yote::ObjManager::fetch_dirty( $login, $guest_token );
	my( $dirty_data );
	if( @$dirty_delta ) {
	    $dirty_data = {};
	    for my $d_id ( @$dirty_delta ) {
		my $dobj = Yote::ObjProvider::fetch( $d_id );
		if( ref( $dobj ) eq 'ARRAY' ) {
		    $dirty_data->{$d_id} = { map { $_ => Yote::ObjProvider::xform_in( $dobj->[$_] ) } (0..$#$dobj) };
		} elsif( ref( $dobj ) eq 'HASH' ) {
		    $dirty_data->{$d_id} = { map { $_ => Yote::ObjProvider::xform_in( $dobj->{ $_ } ) } keys %$dobj };
		} else { # Yote::Obj
		    $dirty_data->{$d_id} = { map { $_ => $dobj->{DATA}{$_} } grep { $_ !~ /^_/ } keys %{$dobj->{DATA}} };
		}
		for my $val (values %{ $dirty_data->{$d_id} } ) {
		    # this registers the objects that were introduced via data structure to the client
		    if( index( $val, 'v' ) != 0 ) {
			Yote::ObjManager::register_object( $val, $login ? $login->{ID} : $guest_token );
		    }
		}
	    }
	    $resp->{d} = $dirty_data;
	} #if there was a dirty delta
    };
    if( $@ ) {
	my $err = $@;
	print STDERR Data::Dumper->Dump(["ERRRR $@",$command]);
	if( $err =~ /^__DEADLOCK__/ ) {
	    iolog( "DEADLOCK TO RETRY $$ : $@" );
	    # if a deadlock condition was detected. back out of any changes and retry
	    # now this could become an issue if things deadlock really really often as the stack would fill up.
#	    print STDERR "[$$ ".time()."] DEADLOCK DETECTED\n";
	    $self->__unlock_all();
	    return $self->__process_command( $command );
	}
	$err =~ s/at \/\S+\.pm.*//s;
        errlog( "ERROR : $@" );
	iolog( "ERROR : $@" );
        $resp = { err => $err, r => '' };
    }
    
    $resp = to_json( $resp );

    $self->__check_locked_for_dirty();
    Yote::ObjProvider::start_transaction();
    Yote::ObjProvider::stow_all();
    Yote::ObjProvider::flush_all_volatile();
    Yote::ObjProvider::commit_transaction();
    $self->__unlock_all();

    ### SEND BACK $resp
    iolog( " * DATA BACK $$ : $resp" );
    #
    # Send return value back to the caller if its waiting for it.
    #
    return $resp

} #__process_command

sub __process_http_request {
    my( $self, $socket ) = @_;
    my $req = <$socket>;

    delete $ENV{'HTTP_CONTENT-LENGTH'};
    while( my $hdr = <$socket> ) {
	$hdr =~ s/\s*$//s;
	last unless $hdr =~ /\S/;
	my( $key, $val ) = ( $hdr =~ /^([^:]+):(.*)/ );
	$ENV{ "HTTP_" . uc( $key ) } = $val;
    }
    my $content_length = $ENV{'HTTP_CONTENT-LENGTH'};
    if( $content_length > 5_000_000 ) { #TODO : make this into a configurable field
	$self->_do404();
	close( $socket );
	return;
    }

    # read certain length from socket ( as many bytes as content length
    my $data;
    if( $content_length && ! eof $socket) {
	my $read = read $socket, $data, $content_length;
    }

    #
    # There are two requests :
    #   * web page
    #   * command. starts with '_'. like _/{app id}/{obj id}/{command} or _/{command}
    #

    # Commands have the following structure :
    #   * a  - action
    #   * ai - app id to invoke command on
    #   * d  - data
    #   * e  - environment
    #   * gt - guest token
    #   * oi - object id to invoke command on
    #   * t  - login token for verification
    #   * gt - app (non-login) guest token for verification
    #   * w  - if true, waits for command to be processed before returning
    #

    my( $verb, $uri, $proto ) = split( /\s+/, $req );
    my $rest;
    ( $uri, $rest ) = ( $uri =~ /([^&?#]+)([&?#]?.*)/ );

    $uri ||= '/index.html';

    $ENV{PATH_INFO} = $uri;
    $ENV{REQUEST_METHOD} = $verb;

    ### ******* $uri **********

    my( @path ) = grep { $_ ne '' && $_ ne '..' } split( /\//, $uri );
    my( @return_headers );
    if( $path[0] eq '_' || $path[0] eq '_u' ) { # _ is normal yote io, _u is upload file
	iolog( "\n$uri" );
	errlog( $uri );
	my $path_start = shift @path;

	my( $wait, $guest_token, $token, $action, $obj_id, $app_id );

	push( @return_headers, "Content-Type: text/json; charset=utf-8");
	push( @return_headers, "Server: Yote" );
	if( $path_start eq '_' ) {
	    ( $app_id, $obj_id, $action, $token, $guest_token, $wait ) = @path;
	    $app_id ||= Yote::ObjProvider::first_id();
	}
	else {
	    my $vars = Yote::FileHelper::__ingest( __parse_form( $socket ) );
	    $data        = $vars->{d};
	    $token       = $vars->{t};
	    $guest_token = $vars->{gt};
	    $wait        = $vars->{w};
	    $action      = pop( @path );
	    $obj_id      = pop( @path );
	    $app_id      = pop( @path ) || Yote::ObjProvider::first_id();
	}
        my $result = $self->__process_command( {
            a  => $action,
            ai => $app_id,
            d  => $data,
	    e  => {%ENV},
            oi => $obj_id,
            t  => $token,
	    gt => $guest_token,
            w  => $wait,
        } );
	print $socket "HTTP/1.0 200 OK\015\012";
	push( @return_headers, "Content-Type: text/json; charset=utf-8" );
	push( @return_headers,  "Access-Control-Allow-Origin: *" );
	push( @return_headers,  "Access-Control-Allow-Headers: accept, content-type, cookie, origin, connection, cache-control " );
	print $socket join( "\n", @return_headers )."\n\n";
	utf8::encode( $result );
	print $socket "$result";
	
    } #if a command on an object

    else { #serve up a web page
	accesslog( "$uri from [ $ENV{REMOTE_ADDR} ][ $ENV{HTTP_REFERER} ]" );
	iolog( $uri );

	my $root = $self->{args}{webroot};
	my $dest = '/' . join('/',@path);

	if( -d "$root/$dest" && ! -f "$root/$dest" ) {
	    if( $dest eq '/' ) {
		$dest = '/index.html';
	    } else {
		$dest = "$dest/index.html";
	    }
	} 
	if( open( my $IN, '<', "$root/$dest" ) ) {

	    print $socket "HTTP/1.0 200 OK\015\012";
	    my $is_html = 0;
	    if( $dest =~ /\.js$/i ) {
		push( @return_headers, "Content-Type: text/javascript" );
	    }
	    elsif( $dest =~ /\.css$/i ) {
		push( @return_headers, "Content-Type: text/css" );
	    }
	    elsif( $dest =~ /\.(jpg|gif|png|jpeg)$/i ) {
		push( @return_headers, "Content-Type: image/$1" );
	    }
	    elsif( $dest =~ /\.(tar|gz|zip|bz2)$/i ) {
		push( @return_headers, "Content-Type: image/$1" );
	    }
	    else {
		push( @return_headers, "Content-Type: text/html" );
		$is_html = 1;
	    }
	    push( @return_headers, "Server: Yote" );
	    print $socket join( "\n", @return_headers )."\n\n";

	    my $size = -s "<$root/$dest";
	    push( @return_headers, "Content-length: $size" );
	    push( @return_headers,  "Access-Control-Allow-Origin: *" );
	    push( @return_headers,  "Access-Control-Allow-Headers: accept, content-type, cookie, origin, connection, cache-control " );

	    my $buf;
	    my $precache_done;
            while( read( $IN,$buf, 8 * 2**10 ) ) {
		if( $is_html && $buf =~ /\<\?YOTE_PRECACHE\s+(\S+)\s*\?\>/ && ! $precache_done ) { 
		    # a web page is almost certainly under the size where the chunking matters.
		    # TODO : cover all cases here
		    # if PRECACHE is checked and $ENV{HTTP_COOKIE} is set
		    ++$precache_done;
		    my $root = Yote::YoteRoot::fetch_root();
		    my $app_name = $1;

		    my $app = $root->fetch_app_by_class( $app_name );
		    if( $app ) {
			my( $acct, $login, $login_token );
			if( $ENV{HTTP_COOKIE} =~ /yoken=([a-f0-9-]+)/ ) {
			    $login_token = $1;
			    $login = $app->token_login( $login_token, undef, \%ENV );
			    if( $login ) {
				$acct = $app->__get_account( $login );
				if( $acct && ( ( $app->get_requires_validation() && ! $login->get__is_validated() ) || $acct->get__is_disabled() ) ) {
				    undef $acct;
				    undef $login;
				} else {
#				    $login_token = $root->_create_token( $login, $ENV{IP} );
				}
			    }
			}
			my $ret = $app->precache( undef, $acct );
			if( $ret ) {
			    my $guest_token = $login_token ? undef : $root->guest_token( $ENV{REMOTE_ADDR} );
			    my $resp = { a  => $app->{ID}, 
					 ap => __obj_to_response( $app, $login, $guest_token ),
					 r  => __obj_to_response( $ret, $login, $guest_token ),
					 gt => $guest_token,
					 t  => $login_token,
					 an => $app_name,
					 ro => __obj_to_response( $root, $login, $guest_token ),
					 lo => $acct ? __obj_to_response( $login, $login, $guest_token ) : undef,
					 ac => $acct ? __obj_to_response( $acct, $login, $guest_token ) : undef,
			    };
			    Yote::ObjProvider::start_transaction();
			    Yote::ObjProvider::stow_all();
			    Yote::ObjProvider::flush_all_volatile();
			    Yote::ObjProvider::commit_transaction();
			    my $json_resp = "window['yote_precache'] = " . to_json( $resp ) . ";";
			    $buf =~ s/(\<\?YOTE_PRECACHE\s+\S+\s*\?\>)/$json_resp/;
			}
		    }
		} #if there is a precache
                print $socket $buf;
            }
            close( $IN );
	    #accesslog( "200 : $dest");
	} else {
	    accesslog( "404 NOT FOUND (".threads->tid().") : $@,$! [$root/$dest]");
	    $self->_do404();
	}
    } #serve html
    close( $socket );
    return;
} #__process_http_request

#
# 
#
sub __parse_form {
    my $socket = shift;
    my $content_length = $ENV{CONTENT_LENGTH} || $ENV{'HTTP_CONTENT-LENGTH'} || $ENV{HTTP_CONTENT_LENGTH};
    my( $finding_headers, $finding_content, %content_data, %post_data, %file_helpers, $fn, $content_type );
    my $boundary_header = $ENV{HTTP_CONTENT_TYPE} || $ENV{'HTTP_CONTENT-TYPE'} || $ENV{CONTENT_TYPE};
    if( $boundary_header =~ /boundary=(.*)/ ) {
	my $boundary = $1;
	my $counter = 0;
	# find boundary parts
	while($counter < $content_length) {
	    $_ = <$socket>;
	    if( /$boundary/s ) {
		last if $1;
		$finding_headers = 1;
		$finding_content = 0;
		if( $content_data{ name } && !$content_data{ filename } ) {
		    $post_data{ $content_data{ name } } =~ s/[\n\r]*$//;
		}
		%content_data = ();
		undef $fn;
	    }
	    elsif( $finding_headers ) {
		if( /^\s*$/s ) {  # got a blank line, so end of headers
		    $finding_headers = 0;
		    $finding_content = 1;
		    if( $content_data{ name } && $content_data{ filename } ) {
			my $name = $content_data{ name };
			
			$fn = File::Temp->new( UNLINK => 0, DIR => $Yote::WebAppServer::FILE_DIR );
			$file_helpers{ $name } = {
			    filename     => $fn->filename,
			    content_type => $content_type,
			}
		    }
		} else {
		    my( $hdr, $val ) = split( /:/, $_ );
		    if( lc($hdr) eq 'content-disposition' ) {
			my( $hdr_type, @parts ) = split( /\s*;\s*/, $val );
			$content_data{ $hdr } = $hdr_type;
			for my $part (@parts) {
			    my( $k, $d, $v ) = ( $part =~ /([^=]*)=(['"])?(.*)\2\s*$/s );
			    $content_data{ $k } = $v;
			}
		    } elsif( lc( $hdr ) eq 'content-type' && $val =~ /^([^;]*)/ ) {
			$content_type = $1;
		    }
		}
	    }
	    elsif( $finding_content ) {
		if( $fn ) {
		    print $fn $_;
		} else {
		    $post_data{ $content_data{ name } } .= $_;
		}
	    } else {

	    }
	    $counter += length( $_ );

	} #while
    } #if has a boundary content type
    return ( \%post_data, \%file_helpers );
} #parse_form

#
# Translates from vValue and reference_id to values and references
#
sub __translate_data {
    my( $val ) = @_;

    if( ref( $val ) eq 'HASH' ) { #from javacript object, or hash. no fields starting with underscores accepted
        return { map {  $_ => __translate_data( $val->{$_} ) } grep { index( $_, '_' ) != 0 } keys %$val };
    }
    elsif( ref( $val ) eq 'ARRAY' ) { #from javacript object, or hash. no fields starting with underscores accepted
        return [ map {  __translate_data( $_ ) } @$val ];
    }
    return unless $val;
    if( index($val,'v') == 0 ) {
	return substr( $val, 1 );
    }
    elsif( index($val,'u') == 0 ) {  #file upload contains an encoded hash
	my $filestruct   = from_json( substr( $val, 1 ) );
	my $filehelper = new Yote::FileHelper();
	$filehelper->set_content_type( $filestruct->{content_type} );
	$filehelper->__accept( $filestruct->{filename} );

	return $filehelper;
    }
    else {
	return Yote::ObjProvider::fetch( $val );
    }
} #__translate_data

#
# Converts scalar, yote object, hash or array to data for returning.
#
sub __obj_to_response {
    my( $to_convert, $login, $guest_token ) = @_;
    my $ref = ref($to_convert);
    my $use_id;
    if( $ref ) {
        my( $m, $d );
        if( $ref eq 'ARRAY' ) {
            my $tied = tied @$to_convert;
            if( $tied ) {
                $d = $tied->[1];
                $use_id = Yote::ObjProvider::get_id( $to_convert );
		for my $entry (@$d) {
		    next unless $entry;
		    if( index( $entry, 'v' ) != 0 ) {
			Yote::ObjManager::register_object( $entry, $login ? $login->{ID} : $guest_token );
		    }
		}
            } else {
                $d = __transform_data_no_id( $to_convert, $login, $guest_token );
            }
        } 
        elsif( $ref eq 'HASH' ) {
            my $tied = tied %$to_convert;
            if( $tied ) {
                $d = $tied->[1];
                $use_id = Yote::ObjProvider::get_id( $to_convert );
		for my $entry (values %$d) {
		    next unless $entry;
		    if( index( $entry, 'v' ) != 0 ) {
			Yote::ObjManager::register_object( $entry, $login ? $login->{ID} : $guest_token );
		    }
		}
            } else {
                $d = __transform_data_no_id( $to_convert, $login, $guest_token );
            }
        } 
        else {
            $use_id = Yote::ObjProvider::get_id( $to_convert );
            $d = { map { $_ => $to_convert->{DATA}{$_} } grep { $_ && $_ !~ /^_/ } keys %{$to_convert->{DATA}}};
	    for my $vl (values %$d) {
		if( index( $vl, 'v' ) != 0 ) {
		    Yote::ObjManager::register_object( $vl, $login ? $login->{ID} : $guest_token );
		}
	    }
	    $m = Yote::ObjProvider::package_methods( $ref );
        }

	Yote::ObjManager::register_object( $use_id, $login ? $login->{ID} : $guest_token ) if $use_id;
	return $m ? { c => $ref, id => $use_id, d => $d, 'm' => $m } : { c => $ref, id => $use_id, d => $d };
    } # if a reference
    return "v$to_convert";
} #__obj_to_response

#
# Transforms data structure but does not assign ids to non tied references.
#
sub __transform_data_no_id {
    my( $item, $login, $guest_token ) = @_;
    if( ref( $item ) eq 'ARRAY' ) {
        my $tied = tied @$item;
        if( $tied ) {
	    my $id =  Yote::ObjProvider::get_id( $item ); 
	    Yote::ObjManager::register_object( $id, $login ? $login->{ID} : $guest_token );
            return $id;
        }
        return [map { __obj_to_response( $_, $login, $guest_token ) } @$item];
    }
    elsif( ref( $item ) eq 'HASH' ) {
        my $tied = tied %$item;
        if( $tied ) {
	    my $id =  Yote::ObjProvider::get_id( $item ); 
	    Yote::ObjManager::register_object( $id, $login ? $login->{ID} : $guest_token );
            return $id;
        }
        return { map { $_ => __obj_to_response( $item->{$_}, $login, $guest_token ) } keys %$item };
    }
    elsif( ref( $item ) ) {
        my $id = Yote::ObjProvider::get_id( $item ); 
	Yote::ObjManager::register_object( $id, $login ? $login->{ID} : $guest_token );
	return $id;
    }
    else {
        return "v$item"; #scalar case
    }
} #__transform_data_no_id


sub __unlock_all {
    my( $self  ) = @_;
    $self->unlock_objects( keys %{ $self->{LOCKED} || {} } );
    $self->{LOCKED} = {};
}


1;

__END__

=head1 NAME

Yote::WebAppServer - This is the app server engine that provides server threads and all javascript perl IO.

=head1 SYNOPSIS

use Yote::WebAppServer;

my $server = new Yote::WebAppServer();

$server->start_server();

=head1 DESCRIPTION

This starts an appslication server running on a specified port and hooked up to a specified datastore.
Additional parameters are passed to the datastore.

=head1 PUBLIC METHODS

=over 4

=item accesslog( msg )

Write the message to the access log

=item errlog( msg )

Write the message to the error log

=item iolog( msg )

Writes to an IO log for client server communications

=item lock_object( obj_id )

Locks the given object id for use by this process only until it is unlocked.

=item new

Returns a new WebAppServer.

=item shutdown( )

Shuts down the yote server, saving all unsaved items.

=item start_server( )

Starts the yote server and launches server threads and activates cron.

=item unlock_objects( @list_of_obj_ids )

Unlocks the objects referenced by the ids passed in. 

=back

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
