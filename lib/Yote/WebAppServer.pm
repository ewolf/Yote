package Yote::WebAppServer;

#
# Proof of concept server with main loop.
#
use strict;

use forks;
use forks::shared;

use CGI;
use Net::Server::HTTP;
use MIME::Base64;
use JSON;
use CGI;
use Data::Dumper;

use Yote::AppRoot;
use Yote::ObjProvider;

use base qw(Net::Server::HTTP);
use vars qw($VERSION);

$VERSION = '0.081';


my( @commands, %prid2wait, %prid2result, $singleton, $cron_id );
share( @commands );
share( %prid2wait );
share( %prid2result );
share( $cron_id );

sub new {
    my $pkg = shift;
    my $class = ref( $pkg ) || $pkg;
    $singleton = bless {}, $class;
    return $singleton;
}

sub start_server {
    my( $self, @args ) = @_;
    my $args = scalar(@args) == 1 ? $args[0] : { @args };
    $self->{args} = $args;
    $self->{args}{webroot} ||= '/usr/local/yote/html';

    Yote::ObjProvider::init( %$args );

    # fork out for three starting threads
    #   - one a multi forking server (parent class)
    #   - and the parent thread an event loop.

    # server thread
    my $server_thread = threads->new( sub { $self->run( %$args ); } );
    $self->{server_thread} = $server_thread;

    # cron thread
#    my $cron_thread = threads->new( sub { $self->loop_cron(); } );

    _poll_commands();

    $server_thread->join;
} #start_server

sub shutdown {
    my $self = shift;
    print STDERR "Shutting down yote server \n";
    &Yote::ObjProvider::stow_all();
    print STDERR "Killing threads \n";
    $self->{server_thread}->detach();
    print STDERR "Shut down server thread.\n";
} #shutdown

#
# Checks every minute to see if any commands were put in the root's cron area.
#
sub loop_cron {
    my $self = shift;
    
    while(1) {
	sleep(60);
	{
	    lock( @commands );
	    my $rnd = int( 10000 * rand() );
	    $cron_id = $rnd;
	    push( @commands, [ { c => 'check_cron', cron_id => $rnd },$$] );
	    print STDERR Data::Dumper->Dump(["Adding Cron Check command"]);
	}
    }

} #loop_cron

#
# Sets up Initial database server and tables.
#
sub init_server {
    my( $self, @args ) = @_;
    Yote::ObjProvider::init_datastore( @args );
} #init_server

#
# Called when a request is made. This does an initial parsing and
# sends a data structure to _process_command.
#
# Commands are sent with a single HTTP request parameter : m for message.
#
# Commands have the following structure :
#   * a - app
#   * c - cmd
#   * d - data
#   * w - if true, waits for command to be processed before returning
#
#
# This ads a command to the list of commands. If
#
#sub process_request {
sub process_http_request {
    my $self = shift;

    #
    # Define here what the paths mean :
    #   GET  /y/i/<app>/<id>?token                   <---- object by id
    #   GET  /y/o/<app>/path/to/obj?token            <---- object by xpath 
    #   GET  /y/r/<app>?token                        <---- app object by app name
    #   GET  anything else, assume a web page
    #
    #   PUT /y/i/<app>/id/method?token,data          <---- run method with posted parameters
    #   PUT /y/o/<app>/path/to/obj/method?token,data <---- run method with posted parameters
    #   PUT /y/r/method                              <---- root method, needs no token
    #
    #   POST  /y/i/<app>/<id>?token                  <---- update object by id
    #   POST  /y/o/<app>/path/to/obj?token           <---- update object by xpath 
    #
    # For POST commands, the following data is included :
    #   m => (base64 encded) {
    #      d:data (ref vs value yote encoded)
    # 
    #
    # 
    #
    my $CGI = new CGI;

    my $command = $CGI->Vars();

    my( $uri, $remote_ip, $verb ) = @ENV{'PATH_INFO','REMOTE_ADDR','REQUEST_METHOD'};

    print STDERR ")START pid $$ : $verb $uri\n";

    my( @path ) = grep { $_ ne '' && $_ ne '..' } split( /\//, $uri );    
    if( $path[0] eq '_' ) {

        # find app or root
        my $app_name = $path[1] eq 'r' ? undef : $path[2];
        
        if( $verb eq 'GET' ) {
	    if( $path[1] eq 'h' ) { #get the human html set up for the app if any
		my $app = Yote::ObjProvider::fetch( "/apps/$app_name" );
		my $html = $app->get_html();
		if( $html ) {
		    print "Content-Type: text/html\n\n$html";
		} else {
		    do404();
		}
		return;
	    }
            my $cmd = $path[1] eq 'r' ? 'get_app' : 'fetch';
            my $id = $path[1] eq 'i' ? $path[3] : '/' . join( '/', @path[3..$#path] );
            if( $path[1] eq 'r' ) {
                $id = '/apps/' . join( '/', @path[2..$#path] );
                $app_name = $path[2];
            }
            #
            # For invoking methods the following is needed :
            #  * id or xpath of object
            #  * app (contained before id or is the first part of the xpath after apps)
            #
            $command = {
                a  => $app_name,
                c  => $cmd,
                id => $id,
                t  => $command->{t},
                w  => 1,
            };
        } # GET
        elsif( $verb eq 'PUT' ) {
            #
            # For invoking methods the following is needed :
            #  * token - to id the account
            #  * command
            #  * id or xpath of object
            #  * app (contained before id or is the first part of the xpath after apps)
            #
            eval {
                $command = from_json( MIME::Base64::decode($command->{m}) );
            };
            if( $@ ) {
                print "{\"err\":\"$@\"}";        
                print STDERR "Got error $@\n";
                print STDERR "<END---------------- PROC REQ $$ ------------------>\n";
                return;
            }
            my $cmd = pop @path;
            my $id = $path[1] eq 'i' ? $path[2] : '/' . join( '/', @path[3..$#path] );

            $command->{a}  = $app_name;
            $command->{c}  = $cmd;
            $command->{id} = $id;
        } # PUT
        elsif( $verb eq 'POST' ) {
            my $id = $path[1] eq 'i' ? $path[3] : '/' . join( '/', @path[3..$#path] );
            my $data = from_json( MIME::Base64::decode($command->{m}) );
            $command = {
                a  => $app_name,
                c  => 'update',
                data  => $data->{data},
                id => $id,
                t  => $command->{t},
                w  => 1,
            };
        } # POST
        $command->{oi} = $remote_ip;
    } 
    else { #serve html
	    my $root = $self->{args}{webroot};
	    my $dest = join('/',@path);
	    if( open( IN, "<$root/$dest" ) ) {
            print "Content-Type: text/html\n\n";
            while(<IN>) {
                print $_;
            }
            close( IN );
	    } else {
		    do404();
	    }
	    return;
    } #serve html

    my $wait = $command->{w};
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
        print STDERR "Sending result $result\n";
        print "Content-Type: text/json\n\n";
        print "$result";
    } else {
        print "{\"msg\":\"Added command\"}";
    }
    print STDERR "<END---------------- PROC REQ $$ ------------------>\n";
    return;
} #process_request

#
# Run by a threat that constantly polls for commands.
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
    }

} #_poll_commands

sub _process_command {
    my $req = shift;
    my( $command, $procid ) = @$req;

    my $wait = $command->{w};

    Yote::ObjProvider::connect();

    my $resp;

    eval {
        my $root = Yote::AppRoot::_fetch_root();
        my $ret  = $root->_process_command( $command );
        $resp = to_json($ret);
        Yote::ObjProvider::stow_all();
    };
    $resp ||= to_json({ err => $@ });

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

    Yote::ObjProvider::disconnect();
} #_process_command

sub do404 {
    print "Content-Type: text/html\n\nERROR : 404\n";
}

1;

__END__

=head1 NAME

Yote::WebAppServer - is a library used for creating prototype applications for the web.

=head1 SYNOPSIS

use Yote::WebAppServer;

my $server = new Yote::WebAppServer();

$server->start_server( port =E<gt> 8008,

=over 32

		       datastore => 'Yote::MysqlIO',
		       db => 'yote_db',
		       uname => 'yote_db_user',
		       pword => 'yote_db-password' );

=back

=head1 DESCRIPTION

This starts an application server running on a specified port and hooked up to a specified datastore.
Additional parameters are passed to the datastore.

The server set up uses Net::Server::Fork receiving and sending messages on multiple threads. These threads queue up the messages for a single threaded event loop to make things thread safe. Incomming requests can either wait for their message to be processed or return immediately.

=head1 BUGS

There are likely bugs to be discovered. This is alpha software

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
