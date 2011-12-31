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
use Data::Dumper;

use GServ::AppProvider;
use GServ::ObjIO;
use CGI;

use base qw(Net::Server::Fork);

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };
$SIG{TERM} = sub {
    Gserv::ObjProvider::stow_all();
    exit;
};

my( @commands, %prid2wait, %prid2result );
share( @commands );
share( %prid2wait );
share( %prid2result );

# find apps to install

our @DBCONNECT;

sub new {
    my $pkg = shift;
    my $class = ref( $pkg ) || $pkg;
    return bless {}, $class;
}
my( $db, $args );
sub start_server {
    my( $self, @args ) = @_;
    $args = scalar(@args) == 1 ? $args[0] : { @args };

    $args->{port}      ||= 8008;
    $args->{datastore} ||= 'GServ::MysqlIO';

    GServ::ObjIO::init( %$args );

    # fork out for two starting threads
    #   - one a multi forking server and the other an event loop.
    print STDERR Data::Dumper->Dump( [$args] );
    my $thread = threads->new( sub { $self->run( max_servers => 2, %$args ); } );

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

#    my( @l ) = `ps ax | grep start_server`;
    print STDERR Data::Dumper->Dump( ["Starting process $$ Request Done"]);#. Pids : ",join(',',map { s/^\s*(\d+).*/$1/;$_ } @l)] );


    my $reqstr = <STDIN>;
    my $params = {map { split(/\=/, $_ ) } split( /\&/, $reqstr )};
    print STDERR Data::Dumper->Dump([$reqstr,$params]);

#    while(<STDIN>) {
#        $reqstr .= $_;
#        last if $_ =~ /^[\n\r]+$/s;
#    }
#    print STDERR Data::Dumper->Dump( [$reqstr] );
#    my $parse_params = HTTP::Request::Params->new( { req => $reqstr } );
#    my $params       = $parse_params->params;
#    my $CGI = new CGI;
#    my $params = $CGI->Vars;
    
    print STDERR Data::Dumper->Dump( [$params,'p1'] );
#    my $callback     = $params->{callback};
    my $command = from_json( MIME::Base64::decode($params->{m}) );
    print STDERR Data::Dumper->Dump( [$command] );

#    return unless $ENV{REMOTE_ADDR} eq '127.0.0.1';
    $command->{oi} = $params->{oi};
#    $command->{oi} = $self->{server}{peeraddr}; #origin ip

    my $wait = $command->{w};
    my $procid = $$;
    {
        lock( %prid2wait );
        $prid2wait{$procid} = $wait;
    }
#    print STDERR Data::Dumper->Dump(["locking comands"]);
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
                cond_wait( %prid2wait );
                last unless $prid2wait{$procid};
            } else {
                last;
            }
        }
        my $result;
        {
#            print STDERR Data::Dumper->Dump( ["loop locking prid2res",\%prid2result] );
            lock( %prid2result );
            $result = $prid2result{$procid};
            delete $prid2result{$procid};
        }
#        print STDERR Data::Dumper->Dump(["after wait ($callback)",$command,$result]);
#        print STDOUT "$callback( '$result' )";
        print STDERR Data::Dumper->Dump(["Printing result",$result]);
        print "$result";
    } else {
        print "{\"msg\":\"Added command\"}";

#        print STDOUT qq|$callback( '{"msg":"Added command"}' );|;
    }
#    my( @l ) = `ps ax | grep start_server`;
    print STDERR Data::Dumper->Dump( ["Process $$ Request Done"] ); #. Pids : ",join(',',map { s/^\s*(\d+).*/$1/;$_ } @l)] );
} #process_request

#
# Run by a threat that constantly polls for commands.
#
sub _poll_commands {
    while(1) {
#        print STDERR Data::Dumper->Dump( ["StartLoop"] );
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

    _reconnect();

    my $resp;

    eval {
        my $root = GServ::AppProvider::fetch_root();
        my $ret  = $root->process_command( $command );
        $resp = to_json($ret);
        GServ::ObjProvider::stow_all();
    };
    $resp ||= to_json({ err => $@ });

    #
    # Send return value back to the caller if its waiting for it.
    #
    lock( %prid2wait );
    {
        lock( %prid2result );
        $prid2result{$procid} = $resp;
    }
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
