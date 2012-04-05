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


my( @commands, %prid2wait, %prid2result, $singleton );
share( @commands );
share( %prid2wait );
share( %prid2result );

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

    _poll_commands();

    $server_thread->join;

    Yote::ObjProvider::disconnect();

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
#
# This ads a command to the list of commands. If
#
#sub process_request {
sub process_http_request {
    my $self = shift;

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
    #   * t  - token for verification
    #   * w  - if true, waits for command to be processed before returning
    #
    my $CGI  = new CGI;
    my $vars = $CGI->Vars();

    my( $uri, $remote_ip, $verb ) = @ENV{'PATH_INFO','REMOTE_ADDR','REQUEST_METHOD'};

    print STDERR ")START pid $$ : $verb $uri\n";

    my( @path ) = grep { $_ ne '' && $_ ne '..' } split( /\//, $uri );    
    if( $path[0] eq '_' ) {

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
            print STDERR "Sending result $result\n";
            print "Content-Type: text/json\n\n";
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
	if( open( IN, "<$root/$dest" ) ) {
	    if( $dest =~ /^yote\/js/ ) {
		print "Content-Type: text/javascript\n\n";
	    }
	    else {
		print "Content-Type: text/html\n\n";
	    }
            while(<IN>) {
                print $_;
            }
            close( IN );
	} else {
	    do404();
	}
#        print STDERR "<END---------------- PROC REQ $$ ------------------>\n";
	return;
    } #serve html

} #process_request

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
    }

} #_poll_commands

sub _process_command {
    my $req = shift;
    my( $command, $procid ) = @$req;

    my $wait = $command->{w};

    my $resp;
    
    Yote::ObjProvider::start_transaction();
    
    eval {
        my $obj_id = $command->{oi};
        my $app_id = $command->{ai};

        my $app        = Yote::ObjProvider::fetch( $app_id );

        my $data       = _translate_data( from_json( MIME::Base64::decode( $command->{d} ) )->{d} );
        my $login = $app->token_login( { t => $command->{t}, _ip => $command->{p} } );
	print STDERR Data::Dumper->Dump(["DATA",$command,  MIME::Base64::decode( $command->{d} ), $data ]);

        my $app_object = Yote::ObjProvider::fetch( $obj_id );
        my $action     = $command->{a};
        my $account;

        # hidden parts of the args
        if( ref( $data ) eq 'HASH' ) {
            $data->{_ip} = $command->{p};
        }

        if( $login ) {
            $account = $app->_get_account( $login );

            if( ! $app->_account_can_access( $account, $app_object ) ) {
                die "Access Error";
            }
        }

        #
        # dirty delta is a list of ids that have changed by this action. It tells the 
        #    client to reload those objects.
        #
        my %before = map { $_ => 1 } (Yote::ObjProvider::dirty_ids());
	print STDERR Data::Dumper->Dump(["doing $action on ", $app_object, 'with data',$data,"and account",$account,'and login',$account?$account->get_login():'none'] );
        my $ret = $app_object->$action( $data, $account );

        my @dirty_delta = grep { ! $before{$_} } ( Yote::ObjProvider::dirty_ids() );

        $resp = { r => $app_object->_obj_to_response( $ret, $account, 1 ), d => \@dirty_delta };
    };
    if( $@ ) {
	my $err = $@;
	$err =~ s/at \/\S+\.pm.*//s;
        print STDERR Data::Dumper->Dump( ["ERROR",$@] );
        $resp = { err => $err, r => '' };
    }

    Yote::ObjProvider::stow_all();
    Yote::ObjProvider::commit_transaction();

    $resp = to_json( $resp );

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
    my $val = shift;

    if( ref( $val ) ) { #from javacript object, or hash. no fields with underscores accepted
        return { map {  $_ => _translate_data( $val->{$_} ) } grep { index( $_, '_' ) == -1 } keys %$val };
    }
    return undef unless $val;
    return index($val,'v') == 0 ? substr( $val, 1 ) : Yote::ObjProvider::fetch( $val );
}

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

$server->start_server();

=head1 DESCRIPTION

This starts an appslication server running on a specified port and hooked up to a specified datastore.
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
