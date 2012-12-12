package Yote::WebAppServer;

use strict;

use forks;
use forks::shared;

use CGI;
use IO::Handle;
use Net::Server::HTTP;
use MIME::Base64;
use JSON;
use Data::Dumper;

use Yote::AppRoot;
use Yote::ObjManager;
use Yote::FileHelper;
use Yote::ObjProvider;

use base qw(Net::Server::HTTP);
use vars qw($VERSION);

$VERSION = '0.081';


my( @commands, %prid2wait, %prid2result, $singleton );
share( @commands );
share( %prid2wait );
share( %prid2result );


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
    $self->send_status( "404 Not Found" );
    print "Content-Type: text/html\n\nERROR : 404\n";
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
    my $self = shift;

    my $content_length = $ENV{CONTENT_LENGTH};
    if( $content_length > 5_000_000 ) { #make this into a configurable field
	$self->do404();
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
    #   * oi - object id to invoke command on
    #   * p  - ip address
    #   * t  - login token for verification
    #   * at - app (non-login) token for verification
    #   * w  - if true, waits for command to be processed before returning
    #

    my( $uri, $remote_ip ) = @ENV{'PATH_INFO','REMOTE_ADDR'};

    print STDERR Data::Dumper->Dump(["REQUEST FOR $uri"]);

    $uri =~ s/\s+HTTP\S+\s*$//;

    my( @path ) = grep { $_ ne '' && $_ ne '..' } split( /\//, $uri );
    print STDERR Data::Dumper->Dump(["PATH : '$path[0]'"]);
    if( $path[0] eq '_' || $path[0] eq '_u' ) { # _ is normal yote io, _u is upload file
	my( $vars, $return_header );

	if( $path[0] eq '_' ) {
	    my $CGI  = new CGI;
	    $vars = $CGI->Vars();
	    $return_header = "Content-Type: text/json\n\n";
	}
	else {
	    $vars = Yote::FileHelper->__ingest();
	    $return_header = "Content-Type: text/html\n\n";
	}

        my $action = pop( @path );
        my $obj_id = int( pop( @path ) ) || 1;
        my $app_id = int( pop( @path ) ) || 1;
        my $wait = $vars->{w};

        my $command = {
            a  => $action,
            ai => $app_id,
            d  => $vars->{d},
            oi => $obj_id,
            p  => $remote_ip,
            t  => $vars->{t},
	    at => $vars->{at},
            w  => $wait,
        };

        my $procid = $$;
        if( $wait ) {
            lock( %prid2wait );
            $prid2wait{$procid} = $wait;
        }

        #
        # Queue up the command for processing in a separate thread.
        #
        {
            lock( @commands );
            push( @commands, [$command, $procid] );
            cond_broadcast( @commands );
        }

        #
        # If the connection is waiting for an answer, give it
        #
        if( $wait ) {
            while( 1 ) {
                my $wait;
                {
                    lock( %prid2wait );
                    $wait = $prid2wait{$procid};
                }
                if( $wait ) {
                    lock( %prid2wait );
                    if( $prid2wait{$procid} ) {
                        cond_wait( %prid2wait );
                    }
                    last unless $prid2wait{$procid};
                } else {
                    last;
                }
            }
            my $result;
            if( $wait ) {
                lock( %prid2result );
                $result = $prid2result{$procid};
                delete $prid2result{$procid};
            }
            print STDERR "Sending result $return_header $result\n";

	    print $return_header;
            print "$result";
        }
        else {  #not waiting for an answer, but give an acknowledgement
            print "{\"msg\":\"Added command\"}";
        }
#        print STDERR "<END---------------- PROC REQ $$ ------------------>\n";
    } #if a command on an object

    else { #serve up a web page
	my $root = $self->{args}{webroot};
	my $dest = join('/',@path);
	if( -d "<$root/$dest" ) {
	    $dest .= '/index.html';
	}
	if( open( IN, "<$root/$dest" ) ) {
	    if( $dest =~ /\.js$/i ) {
		print "Content-Type: text/javascript\n\n";
	    }
	    elsif( $dest =~ /\.css$/i ) {
		print "Content-Type: text/css\n\n";
	    }
	    elsif( $dest =~ /\.(jpg|gif|png|jpeg)$/i ) {
		print "Content-Type: image/$1\n\n";
	    }
	    else {
		print "Content-Type: text/html\n\n";
	    }
            while(<IN>) {
                print $_;
            }
            close( IN );
	} else {
	    $self->do404();
	}
	return;
    } #serve html

} #process_request


sub shutdown {
    my $self = shift;
    print STDERR "Shutting down yote server \n";
    Yote::ObjProvider::stow_all();
    print STDERR "Killing threads \n";
    $self->{server_thread}->detach();
    $self->{saving_thread}->detach();
    print STDERR "Shut down server thread.\n";
} #shutdown

sub start_server {
    my( $self, @args ) = @_;
    my $args = scalar(@args) == 1 ? $args[0] : { @args };
    $self->{args} = $args;
    $self->{args}{webroot} ||= '/usr/local/yote/html';
    $self->{args}{upload} ||= '/usr/local/yote/html/upload';

    Yote::ObjProvider::init( %$args );

    # fork out for three starting threads
    #   - one a multi forking server (parent class)
    #   - one for a cron daemon inside of Yote. (PENDING)
    #   - and the parent thread an event loop.

    my $root = Yote::YoteRoot::fetch_root();

    # @TODO - finish the cron and uncomment this
    # cron thread
    #my $cron = $root->get__crond();
    #my $cron_thread = threads->new( sub { $self->_crond( $cron->{ID} ); } );
    #$self->{cron_thread} = $cron_thread;

    # make sure the filehelper knows where the data directory is
    $Yote::WebAppServer::YOTE_ROOT_DIR = $self->{args}{root_dir};
    $Yote::WebAppServer::DATA_DIR      = $self->{args}{data_dir};
    $Yote::WebAppServer::FILE_DIR      = $self->{args}{data_dir} . '/holding';
    $Yote::WebAppServer::WEB_DIR       = $self->{args}{webroot};
    $Yote::WebAppServer::UPLOAD_DIR    = $self->{args}{webroot}. '/uploads';
    mkdir( $Yote::WebAppServer::DATA_DIR );
    mkdir( $Yote::WebAppServer::FILE_DIR );
    mkdir( $Yote::WebAppServer::WEB_DIR );
    mkdir( $Yote::WebAppServer::UPLOAD_DIR );

    # update @INC library list
    my $paths = $root->get__application_lib_directories([]);
    push @INC, @$paths;

    # server thread
    my $server_thread = threads->new( sub { $self->run( %$args ); } );
    $self->{server_thread} = $server_thread;

    _poll_commands();

    $server_thread->join;

   Yote::ObjProvider::disconnect();

} #start_server



# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------


sub _crond {
    my( $self, $cron_id ) = @_;

    while( 1 ) {
	sleep( 60 );
	{
	    lock( @commands );
	    push( @commands, [ {
		a  => 'check',
		ai => 1,
		d  => 'eyJkIjoxfQ==',
		oi => $cron_id,
		p  => undef,
		t  => undef,
		w  => 0,
			       }, $$] );
	    cond_broadcast( @commands );
	}
    } #infinite loop

} #_crond

#
# Run by a thread that constantly polls for commands.
#
sub _poll_commands {
    while(1) {
        my $cmd;
        {
            lock( @commands );
            $cmd = shift @commands;
        }
        if( $cmd ) {
            _process_command( $cmd );
        }
        unless( @commands ) {
            lock( @commands );
            cond_wait( @commands );
        }
	if( $cmd ) {
	    Yote::ObjProvider::start_transaction();
	    Yote::ObjProvider::stow_all();
	    Yote::ObjProvider::commit_transaction();
	}
    }

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
        my $login       = $app->token_login( $command->{t}, undef, $command->{p} );
	my $guest_token = $command->{gt};

	print STDERR Data::Dumper->Dump(["INCOMING",$data,$command,$login]);

	# security check
	unless( Yote::ObjManager::allows_access( $obj_id, $app, $login, $guest_token ) ) {
	    die "Access Error";
	}

        my $app_object = Yote::ObjProvider::fetch( $obj_id ) || $app;
        my $action     = $command->{a};
        my $account;
        if( $login ) {
            $account = $app->__get_account( $login );
        }
	Yote::ObjProvider::reset_changed();

        my $ret = $app_object->$action( $data, $account, $command->{p} );

	my $dirty_delta = Yote::ObjProvider::__fetch_changed();

	my( $dirty_data );
	if( @$dirty_delta ) {
	    $dirty_data = {};
	    my $allowed_dirty = Yote::ObjManager::knows_dirty( $dirty_delta, $app_object, $login, $guest_token );
	    for my $d_id ( @$allowed_dirty ) {
		my $dobj = Yote::ObjProvider::fetch( $d_id );
		if( ref( $dobj ) eq 'ARRAY' ) {
		    $dirty_data->{$d_id} = { map { $_ => Yote::ObjProvider::xform_in( $dobj->[$_] ) } (0..$#$dobj) };
		} elsif( ref( $dobj ) eq 'HASH' ) {
		    $dirty_data->{$d_id} = { map { $_ => Yote::ObjProvider::xform_in( $dobj->{ $_ } ) } keys %$dobj };
		} else {
		    $dirty_data->{$d_id} = { map { $_ => $dobj->{DATA}{$_} } grep { $_ !~ /^_/ } keys %{$dobj->{DATA}} };
		}
	    }
	} #if there was a dirty delta

        $resp = $dirty_data ? { r => $app_object->__obj_to_response( $ret, $login, 1, $guest_token ), d => $dirty_data } : { r => $app_object->__obj_to_response( $ret, $login, 1, $guest_token ) };

#	if( $login ) {
#	    $Yote::ObjProvider::LOGIN_OBJECTS->{ $login->{ID} }{ $app_object->{ID} } = 1;
#	}
	
    };
    if( $@ ) {
	my $err = $@;
	$err =~ s/at \/\S+\.pm.*//s;
        print STDERR Data::Dumper->Dump( ["ERROR",$@] );
        $resp = { err => $err, r => '' };
    }

    $resp = to_json( $resp );
    print STDERR Data::Dumper->Dump(["SEND BACK", $resp]);

    #
    # Send return value back to the caller if its waiting for it.
    #
    if( $wait ) {
        lock( %prid2wait );
        {
            lock( %prid2result );
            $prid2result{$procid} = $resp;
        }
        delete $prid2wait{$procid};
        cond_broadcast( %prid2wait );
    }


} #_process_command

#
# Translates from vValue and reference_id to values and references
#
sub _translate_data {
    my( $val ) = @_;

    if( ref( $val ) ) { #from javacript object, or hash. no fields starting with underscores accepted
        return { map {  $_ => _translate_data( $val->{$_} ) } grep { index( $_, '_' ) != 0 } keys %$val };
    }
    return undef unless $val;
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
}

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

=item do404

Return a 404 not found page and exit.

=item process_http_request( )

This implements Net::Server::HTTP and is called automatically for each incomming request.

=item shutdown( )

Shuts down the yote server, saving all unsaved items.

=item start_server( )

=back

=head1 BUGS

There are likely bugs to be discovered. This is alpha software.

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
