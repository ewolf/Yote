package GServ::AppServer;

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

use GServ::AppRoot;
use GServ::ObjIO;

use base qw(Net::Server::Fork);

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

my( @commands, %prid2wait, %prid2result, $singleton );
share( @commands );
share( %prid2wait );
share( %prid2result );

$SIG{TERM} = sub { 
    $singleton->server_close();
    &GServ::ObjProvider::stow_all();
    print STDERR Data::Dumper->Dump(["Shutting down due to term"]);
    exit;
};

sub new {
    my $pkg = shift;
    my $class = ref( $pkg ) || $pkg;
    $singleton = bless {}, $class;
    return $singleton;
}
my( $db, $args );
sub start_server {
    my( $self, @args ) = @_;
    $args = scalar(@args) == 1 ? $args[0] : { @args };

    # load config file
    my $file = `cat /home/irrespon/var/gserv.conf`;
    my $config_data = from_json( $file );

    $args->{port}      = $args->{port}      || $config_data->{port}      || 8008;
    $args->{datastore} = $args->{datastore} || $config_data->{datastore} || 'GServ::MysqlIO';
    $args->{pidfile}   = $args->{pidfile}   || $config_data->{pidfile} || '/home/irrespon/var/run/gserv.pid';
    for my $key (keys %$config_data) {
	$args->{$key} ||= $config_data->{$key};
    }

    `cat $args->{pidfile} | xargs kill`;
    `echo $$ > $args->{pidfile}`;

    print STDERR Data::Dumper->Dump([$file, $config_data,$args]);
    

    GServ::ObjIO::init( %$args );

    # fork out for two starting threads
    #   - one a multi forking server and the other an event loop.
    print STDERR Data::Dumper->Dump( [$args] );
    my $thread = threads->new( sub { $self->run( %$args ); } );

    _poll_commands();

    $thread->join;
} #start_server

#
# Sets up Initial database server and tables.
#
sub init_server {
    my( $self, @args ) = @_;
    GServ::ObjIO::init_datastore( @args );
} #init_server

#
# Called when a request is made. This does an initial parsing and
# sends a data structure to process_command.
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

    my $reqstr = <STDIN>;
    my $params = {map { split(/\=/, $_ ) } split( /\&/, $reqstr )};

    
    my $command = from_json( MIME::Base64::decode($params->{m}) );
    print STDERR Data::Dumper->Dump( [$command,'Inputted Command'] );

#    return unless $ENV{REMOTE_ADDR} eq '127.0.0.1';
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
                lock( %prid2wait );
                $wait = $prid2wait{$procid};
            }
            if( $wait ) {
                lock( %prid2wait );
                cond_wait( %prid2wait );
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
	    print STDERR Data::Dumper->Dump([" in poll, Processing",$cmd]);
            _process_command( $cmd );
	    print STDERR Data::Dumper->Dump([" in poll, Done processing",$cmd]);
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

    _reconnect();

    my $resp;

    eval {
        my $root = GServ::AppRoot::fetch_root();
        my $ret  = $root->process_command( $command );
        $resp = to_json($ret);
        GServ::ObjProvider::stow_all();
    };
    $resp ||= to_json({ err => $@ });

    #
    # Send return value back to the caller if its waiting for it.
    #
    print STDERR Data::Dumper->Dump(["IN process, locking prid2wait for",$resp]);
    lock( %prid2wait );
    {
    print STDERR Data::Dumper->Dump(["IN process, locking prid2result for",$resp]);
        lock( %prid2result );
        $prid2result{$procid} = $resp;
    }
    print STDERR Data::Dumper->Dump(["IN process, freeing prid2wait for",$resp]);

    delete $prid2wait{$procid};
    cond_broadcast( %prid2wait );

} #_process_command

sub _reconnect {
    GServ::ObjIO::reconnect();
} #_reconnect

1

__END__

=head1 NAME

GServ::AppServer - is a library used for creating prototype applications for the web.

=head1 SYNOPSIS

    use GServ::AppServer;
    use GServ::ObjIO::DB;
    use GServ::AppServer;

    my $persistance_engine = new GServ::ObjIO::DB(connection params);
    $persistance_engine->init_gserv;

    my $server = new GServ::AppServer( persistance => $persistance_engine );

    # --- or ----
    my $server = new GServ::AppServer;
    $server->attach_persistance( $persistance_engine );

    $server->start_server( port => 8008 );

=head1 DESCRIPTION



=head1 BUGS

Given that this is pre pre alpha. Many yet undiscovered.

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
