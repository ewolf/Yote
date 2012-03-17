package Yote::WebAppServer;

#
# Proof of concept server with main loop.
#
use strict;

use forks;
use forks::shared;

use HTTP::Request::Params;
use Net::Server::Fork;
use MIME::Base64;
use JSON;
use CGI;
use Data::Dumper;

use Yote::AppRoot;

use base qw(Net::Server::Fork);
use vars qw($VERSION);

$VERSION = '0.080';


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

    Yote::ObjProvider::init( %$args );

    # fork out for two starting threads
    #   - one a multi forking server and the other an event loop.
    my $thread = threads->new( sub { $self->run( %$args ); } );
    $self->{thread} = $thread;

    _poll_commands();

    $thread->join;
} #start_server

sub shutdown {
    my $self = shift;
    print STDERR "Shutting down yote server \n";
    &Yote::ObjProvider::stow_all();
    print STDERR "Killing threads \n";
    $self->{thread}->detach();
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
# Commands have the following structure :
#   * a - app
#   * c - cmd
#   * d - data
#   * w - if true, waits for command to be processed before returning
#
#
# This ads a command to the list of commands. If
#
sub process_request {
    my $self = shift;

    print STDERR ")START---------------- PROC REQ $$ ------------------(\n";

    my $reqstr = <STDIN>;
    my $params = {map { split(/\=/, $_ ) } split( /\&/, $reqstr )};

    
    my $command;
    eval {
        $command = from_json( MIME::Base64::decode($params->{m}) );
    };
    if( $@ ) {
        print "{\"err\":\"$@\"}";        
        print STDERR "Got error $@\n";
        print STDERR "<END---------------- PROC REQ $$ ------------------>\n";
        return;
    }
    print STDERR Data::Dumper->Dump( [$command,'Inputted Command'] );

    $command->{oi} = $params->{oi};

    my $wait = $command->{w};
    my $procid = $$;
    {
        print STDERR Data::Dumper->Dump(["Lock prid2wait"]);
        lock( %prid2wait );
        $prid2wait{$procid} = $wait;
        print STDERR Data::Dumper->Dump(["Locked prid2wait"]);
    }

    #
    # Queue up the command for processing in a separate thread.
    #
    {
        print STDERR Data::Dumper->Dump(["Lock commands"]);
        lock( @commands );
        print STDERR Data::Dumper->Dump(["Locked commands"]);
        push( @commands, [$command, $procid] );
        cond_broadcast( @commands );
    }


    if( $wait ) {
        while( 1 ) {
            my $wait;
            {
                print STDERR "process request lock prid2wait\n";
                lock( %prid2wait );
                $wait = $prid2wait{$procid};
                print STDERR "process request locked prid2wait. got wait '$wait'\n";
            }
            if( $wait ) {
                print STDERR "process request lock prid2wait for wait\n";
                lock( %prid2wait );
                print STDERR "process request cond wait prid2wait for wait\n";
                if( $prid2wait{$procid} ) {
                    cond_wait( %prid2wait );
                }
                print STDERR "process request cond wait done prid2wait for wait. procid ($procid)\n";
                print STDERR  Data::Dumper->Dump([\%prid2wait]);
                last unless $prid2wait{$procid};
            } else {
                last;
            }
        }
        my $result;
        {
            lock( %prid2result );
            $result = $prid2result{$procid};
            delete $prid2result{$procid};
        }
        print STDERR Data::Dumper->Dump([$result,"Result to Send"]);
        print "$result";
    } else {
        print "{\"msg\":\"Added command\"}";
    }
    print STDERR "<END---------------- PROC REQ $$ ------------------>\n";

} #process_request

#
# Run by a threat that constantly polls for commands.
#
sub _poll_commands {
    while(1) {
        my $cmd;
        {
            print STDERR "Extracting Command\n";
            lock( @commands );
            $cmd = shift @commands;
            print STDERR "Got Command\n";
        }
        if( $cmd ) {
            print STDERR ">===================== START Processing command (poll $$) ============<\n";
            _process_command( $cmd );
            print STDERR ">===================== DONE Processing command (poll $$) ============<\n";
        }
        unless( @commands ) {
            print STDERR "Locking commands\n";
            lock( @commands );
            print STDERR "Waiting for commands\n";
            cond_wait( @commands );
            print STDERR "Got Command\n";
        }
    }

} #_poll_commands

sub _process_command {
    my $req = shift;
    my( $command, $procid ) = @$req;

    Yote::ObjProvider::connect();

    my $resp;

    eval {
        my $root = Yote::AppRoot::fetch_root();
        my $ret  = $root->_process_command( $command );
        print STDERR Data::Dumper->Dump(["Process command response : ",$ret]);
        $resp = to_json($ret);
        Yote::ObjProvider::stow_all();
    };
    $resp ||= to_json({ err => $@ });

    #
    # Send return value back to the caller if its waiting for it.
    #
    print STDERR " _process_command Lock prid2wait\n";
    lock( %prid2wait );
    print STDERR " _process_command Locked prid2wait\n";
    {
        lock( %prid2result );
        $prid2result{$procid} = $resp;
    }
    print STDERR Data::Dumper->Dump(["IN process, freeing prid2wait for process ($procid)",$resp,\%prid2wait]);

    delete $prid2wait{$procid};
    print STDERR " _process_command Broadcast prid2wait (deleted $procid)\n";
    cond_broadcast( %prid2wait );
    print STDERR " _process_command Broadcasted prid2wait\n";

    Yote::ObjProvider::commit();
    Yote::ObjProvider::disconnect();
} #_process_command

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
