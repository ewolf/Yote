package Yote::WebAppServer;

use strict;
use warnings;
no warnings 'uninitialized';

use forks;
use forks::shared;

use Data::Dumper;
use MIME::Base64;
use IO::Handle;
use IO::Socket;
use JSON;
use POSIX qw(strftime);

use Yote::AppRoot;
use Yote::ObjManager;
use Yote::FileHelper;
use Yote::ObjProvider;

use vars qw($VERSION);

$VERSION = '0.092';


my( %prid2result, $singleton );
share( %prid2result );

use Thread::Queue;

my $cmd_queue = Thread::Queue->new();


# ------------------------------------------------------------------------------------------
#      * INIT METHODS *
# ------------------------------------------------------------------------------------------

sub new {
    my $pkg = shift;
    my $class = ref( $pkg ) || $pkg;
    $singleton = bless {}, $class;
    return $singleton;
}

#
# Sets up Initial database server and tables.
#
sub init_server {
    my( $self, @args ) = @_;
   Yote::ObjProvider::init_datastore( @args );
} #init_server

# ------------------------------------------------------------------------------------------
#      * PUBLIC METHODS *
# ------------------------------------------------------------------------------------------


sub do404 {
    my $self = shift;
    print "HTTP/1.0 404 NOT FOUND\015\012Content-Type: text/html\n\nERROR : 404\n";
}


sub iolog {
    my( $msg ) = @_;
    my $t = strftime "%Y-%m-%d %H:%M:%S", gmtime;
    print $Yote::WebAppServer::IO "$t : $msg\n";
}

sub errlog {
    my( $msg ) = @_;
    my $t = strftime "%Y-%m-%d %H:%M:%S", gmtime;
    print $Yote::WebAppServer::ERR "$t : $msg\n";
}

sub accesslog {
    my( $msg ) = @_;
    my $t = strftime "%Y-%m-%d %H:%M:%S", gmtime;
    print $Yote::WebAppServer::ACCESS "$t : $msg\n";
}

#
# Called when a request is made. This does an initial parsing and
# sends a data structure to _process_command.
#
# Commands are sent with a single HTTP request parameter : m for message.
#
#
# This ads a command to the list of commands. If
#
#sub process_request {
sub process_http_request {
    my( $self, $soc ) = @_;

    my $req = <$soc>;

    while( my $hdr = <$soc> ) {
	$hdr =~ s/\s*$//s;
	last unless $hdr =~ /\S/;
	my( $key, $val ) = ( $hdr =~ /^([^:]+):(.*)/ );
	$ENV{ "HTTP_" . uc( $key ) } = $val;
    }

    my $content_length = $ENV{CONTENT_LENGTH};
    if( $content_length > 5_000_000 ) { #make this into a configurable field
	$self->do404();
	close( $soc );
	return;
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
	iolog( $uri );
	errlog( $uri );
	my $path_start = shift @path;

	my( $data, $wait, $guest_token, $token, $action, $obj_id, $app_id );

	push( @return_headers, "Content-Type: text/json; charset=utf-8");
	push( @return_headers, "Server: Yote" );
	if( $path_start eq '_' ) {
	    ( $app_id, $obj_id, $action, $token, $guest_token, $wait, $data ) = @path;
	    $app_id ||= Yote::ObjProvider::first_id();
	}
	else {
	    my $vars = Yote::FileHelper::__ingest( _parse_form( $soc ) );
	    $data        = $vars->{d};
	    $token       = $vars->{t};
	    $guest_token = $vars->{gt};
	    $wait        = $vars->{w};
	    $action      = pop( @path );
	    $obj_id      = pop( @path );
	    $app_id      = pop( @path ) || Yote::ObjProvider::first_id();
	}

        my $command = {
            a  => $action,
            ai => $app_id,
            d  => $data,
	    e  => {%ENV},
            oi => $obj_id,
            t  => $token,
	    gt => $guest_token,
            w  => $wait,
        };

        my $procid = $$;

        #
        # Queue up the command for processing in a separate thread.
        #
	$cmd_queue->enqueue( [$command, $procid ] );

        #
        # If the connection is waiting for an answer, give it
        #
        if( $wait ) {
	    my $result;
            while( 1 ) {
                lock( %prid2result );
                $result = $prid2result{$procid};
		if( defined( $result ) ) {
		    delete $prid2result{$procid};
		    last;
		}
		else {
		    cond_wait( %prid2result );
		}
		sleep 0.001;
            }
	    print $soc "HTTP/1.0 200 OK\015\012";
	    push( @return_headers, "Content-Type: text/json; charset=utf-8" );
	    push( @return_headers,  "Access-Control-Allow-Origin: *" );
	    print $soc join( "\n", @return_headers )."\n\n";
	    utf8::encode( $result );
            print $soc "$result";
        }
        else {  #not waiting for an answer, but give an acknowledgement
	    print $soc "HTTP/1.0 200 OK\015\012";
	    push( @return_headers, "Content-Type: text/json; charset=utf-8" );
	    push( @return_headers,  "Access-Control-Allow-Origin: *" );
	    print $soc join( "\n", @return_headers )."\n\n";
            print $soc "{\"msg\":\"Added command\"}";
        }
    } #if a command on an object

    elsif( $path[0] eq '_c' ) {
	# modify the file helper ingest method, splitting out the part that returns the form
	# call the method that returns the form ( maybe move that method here )
    } #if a 'cgi' is requested

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

	    print $soc "HTTP/1.0 200 OK\015\012";
	    my $binary = 0;
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
	    }
	    push( @return_headers, "Server: Yote" );
	    print $soc join( "\n", @return_headers )."\n\n";

	    my $size = -s "<$root/$dest";
	    push( @return_headers, "Content-length: $size" );
	    push( @return_headers,  "Access-Control-Allow-Origin: *" );

	    my $buf;
            while( read( $IN,$buf, 8 * 2**10 ) ) {
                print $soc $buf;
            }
            close( $IN );
	    #accesslog( "200 : $dest");
	} else {
	    accesslog( "404 NOT FOUND : $@,$! $root/$dest");
	    $self->do404();
	}
	close( $soc );
	return;
    } #serve html

} #process_request


sub shutdown {
    my $self = shift;
    accesslog( "Shutting down yote server" );
    Yote::ObjProvider::start_transaction();
    Yote::ObjProvider::stow_all();
    Yote::ObjProvider::commit_transaction();
    accesslog(  "Killing threads" );
    $self->_stop_threads();
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

    Yote::ObjProvider::init( %$args );

    # fork out for three starting threads
    #   - one a multi forking server (parent class)
    #   - one for a cron daemon inside of Yote. (PENDING)
    #   - and the parent thread an event loop.

    my $root = Yote::YoteRoot::fetch_root();

    # check for default account and set its password from the config.
    $root->_check_root( $args->{ root_account }, $args->{ root_password } );

    # @TODO - finish the cron and uncomment this
    # cron thread
    #my $cron = $root->get__crond();
    #my $cron_thread = threads->new( sub { $self->_crond( $cron->{ID} ); } );
    #$self->{cron_thread} = $cron_thread;

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

    # update @INC library list
    my $paths = $root->get__application_lib_directories([]);
    push @INC, @$paths;

    $self->{lsn} = new IO::Socket::INET(Listen => 10, LocalPort => $self->{args}{port}) or die $@;

    $self->{threadcount} = 5;

    $self->{threads} = [];

    for( 1 .. $self->{threadcount} ) {
	$self->_start_server_thread;
    } #creating 5 threads

    $self->{watchdog_thread} = threads->new(
	sub {
	    while( 1 ) {
		sleep( 5 );
		$self->{threads} = [ grep { $_->is_running } @{$self->{threads}}];
		while( @{$self->{threads}} < $self->{threadcount} ) {
		    $self->_start_server_thread;
		}
	    }
	} );

    _poll_commands();

    _stop_threads();

   Yote::ObjProvider::disconnect();

} #start_server

# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

sub _stop_threads {
    my $self = shift;
    $self->{watchdog_thread}->kill if $self->{watchdog_thread} && $self->{watchdog_thread}->is_running;
    for my $thread (@{$self->{threads}}) {
	$thread->kill if $thread && $thread->is_running;
    }
}

sub _start_server_thread {
    my $self = shift;
    push( @{ $self->{threads} },
	  threads->new(
	      sub {
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
		      $ENV{ REMOTE_ADDR } = $fh->peerhost;
		      $self->process_http_request( $fh );
		      $fh->close();
		  } #main loop
	      } ) #new thread
	);
} #_start_server_thread


sub _crond {
    my( $self, $cron_id ) = @_;

    while( 1 ) {
	sleep( 60 );
	{
	    $cmd_queue->enqueue( [ {
		a  => 'check',
		ai => 1,
		d  => 'eyJkIjoxfQ==',
		e  => {%ENV},
		oi => $cron_id,
		t  => undef,
		w  => 0,
				   }, $$]
		);
	}
    } #infinite loop

} #_crond

#
# Run by a thread that constantly polls for commands.
#
sub _poll_commands {

    while(1) {
	_process_command( $cmd_queue->dequeue() );
	Yote::ObjProvider::start_transaction();
	Yote::ObjProvider::stow_all();
	Yote::ObjProvider::commit_transaction();
    } #endlees loop

} #_poll_commands

sub _process_command {
    my( $req ) = @_;
    my( $command, $procid ) = @$req;
    my $wait = $command->{w};

    my $resp;

    eval {
        my $obj_id = $command->{oi};
        my $app_id = $command->{ai};

        my $app         = Yote::ObjProvider::fetch( $app_id ) || Yote::YoteRoot::fetch_root();

        my $data        = _translate_data( from_json( MIME::Base64::decode( $command->{d} ) )->{d} );
	
	iolog( "  * DATA IN  : " . Data::Dumper->Dump( [ $data ] ) );

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
            $account = $app->__get_account( $login );
	    $account->set_login( $login ); # security measure to make sure login can't be overridden by a subclass of account
	    $login->add_once_to__accounts( $account );
        }

        my $ret = $app_object->$action( $data, $account, $command->{e} );

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
		} else {
		    $dirty_data->{$d_id} = { map { $_ => $dobj->{DATA}{$_} } grep { $_ !~ /^_/ } keys %{$dobj->{DATA}} };
		}
		for my $val (values %{ $dirty_data->{$d_id} } ) {
		    if( index( $val, 'v' ) != 0 ) {
			Yote::ObjManager::register_object( $val, $login ? $login->{ID} : $guest_token );
		    }
		}
	    }
	} #if there was a dirty delta
        $resp = $dirty_data ? { r => $app_object->__obj_to_response( $ret, $login, $guest_token ), d => $dirty_data } : { r => $app_object->__obj_to_response( $ret, $login, $guest_token ) };
    };
    if( $@ ) {
	my $err = $@;
	$err =~ s/at \/\S+\.pm.*//s;
        errlog( "ERROR : $@" );
	iolog( "ERROR : $@" );
        $resp = { err => $err, r => '' };
    }

    $resp = to_json( $resp );

    ### SEND BACK $resp
    iolog( " * DATA BACK : $resp" );

    #
    # Send return value back to the caller if its waiting for it.
    #
    if( $wait ) {
	lock( %prid2result );
	$prid2result{$procid} = $resp;
        cond_signal( %prid2result );
    }


} #_process_command

#
# 
#
sub _parse_form {
    my $soc = shift;
    my $content_length = $ENV{CONTENT_LENGTH} || $ENV{'HTTP_CONTENT-LENGTH'} || $ENV{HTTP_CONTENT_LENGTH};
    my( $finding_headers, $finding_content, %content_data, %post_data, %file_helpers, $fn, $content_type );
    my $boundary_header = $ENV{HTTP_CONTENT_TYPE} || $ENV{'HTTP_CONTENT-TYPE'} || $ENV{CONTENT_TYPE};
    if( $boundary_header =~ /boundary=(.*)/ ) {
	my $boundary = $1;
	my $counter = 0;
	# find boundary parts
	while($counter < $content_length) {
	    $_ = <$soc>;
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
sub _translate_data {
    my( $val ) = @_;

    if( ref( $val ) eq 'HASH' ) { #from javacript object, or hash. no fields starting with underscores accepted
        return { map {  $_ => _translate_data( $val->{$_} ) } grep { index( $_, '_' ) != 0 } keys %$val };
    }
    elsif( ref( $val ) eq 'ARRAY' ) { #from javacript object, or hash. no fields starting with underscores accepted
        return [ map {  _translate_data( $_ ) } @$val ];
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
} #_translate_data

1;

__END__

=head1 NAME

Yote::WebAppServer - is a library used for creating prototype applications for the web.

=head1 SYNOPSIS

use Yote::WebAppServer;

my $server = new Yote::WebAppServer();

$server->start_server();

=head1 DESCRIPTION

This starts an appslication server running on a specified port and hooked up to a specified datastore.
Additional parameters are passed to the datastore.

The server set up uses Net::Server::Fork receiving and sending messages on multiple threads. These threads queue up the messages for a single threaded event loop to make things thread safe. Incomming requests can either wait for their message to be processed or return immediately.

=head1 PUBLIC METHODS

=over 4

=item accesslog( msg )

Write the message to the access log

=item do404

Return a 404 not found page and exit.

=item errlog( msg )

Write the message to the error log

=item iolog( msg )

Writes to an IO log for client server communications

=item init_server

=item new

Returns a new WebAppServer.

Sets up Initial database server and tables.

=item process_http_request( )

This implements Net::Server::HTTP and is called automatically for each incomming request.

=item shutdown( )

Shuts down the yote server, saving all unsaved items.

=item start_server( )

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
