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

use base qw(Net::Server::Fork);

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

my( @commands, %prid2wait, %prid2result );
share( @commands );
share( %prid2wait );
share( %prid2result );

# find apps to install
require GServ::Hello;

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
    $args->{port} ||= 8008;
    $db = $args->{database} || 'sg';

    print STDERR Data::Dumper->Dump( ["Start TO Start"] );
    #make sure this thread has a valid database connectin
    @DBCONNECT = ( "DBI:mysql:$db", $args->{uname}, $args->{password} );

    # fork out for two starting threads
    #   - one a multi forking server and the other an event loop.

    my $thread = threads->new( sub { $self->run( %$args ); } );
    print STDERR Data::Dumper->Dump( ["Threaded"] );
#    $self->run( %$args );
    print STDERR Data::Dumper->Dump(['server running']);

    _poll_commands();

    $thread->join;
} #start_server

#
# Sets up Initial database server and tables.
#
sub init_server {
    my( $self, @args ) = @_;
    my $args = scalar(@args) == 1 ? $args[0] : { @args };
    die "Must specify database in args to init_server" unless $args->{database};
    
    GServ::ObjIO::init_database( $args->{database} );
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

    my $reqstr;
    while(<STDIN>) {
        $reqstr .= $_;
        last if $_ =~ /^[\n\r]+$/s;
    }
    print STDERR Data::Dumper->Dump( [$reqstr] );
    my $parse_params = HTTP::Request::Params->new( { req => $reqstr } );
    my $params       = $parse_params->params;
    my $callback     = $params->{callback};
    my $command = from_json( MIME::Base64::decode($params->{m}) );
    print STDERR Data::Dumper->Dump( [$params,$command] );
    $command->{oi} = $self->{server}{peeraddr}; #origin ip

    my $wait = $command->{w};
    my $procid = $$;
    {
        lock( %prid2wait );
        $prid2wait{$procid} = $wait;
    }
    print STDERR Data::Dumper->Dump(["locking comands"]);
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
	    my $do_wait;
	    {
		print STDERR Data::Dumper->Dump(["pr $$ ($procid) checking wait to lock"]);
		lock( %prid2wait );
		print STDERR Data::Dumper->Dump(["pr locked wait"]);
		$do_wait = $prid2wait{$procid};
	    }
	    if( $do_wait ) {
		print STDERR Data::Dumper->Dump(["pr checking wait to cond_wait"]);
		lock( %prid2wait ); 
		print STDERR Data::Dumper->Dump(["pr checking wait to cond_wait Locked $@"]);
		cond_wait( %prid2wait );
		print STDERR Data::Dumper->Dump(["pr checking cond_wait Over",$@]);
		last unless $prid2wait{$procid};
	    } else {
		last;
	    }
	}
	my $result;
	{
	    print STDERR Data::Dumper->Dump(["PR lock res",%prid2result]);
	    lock( %prid2result );
	    print STDERR Data::Dumper->Dump(["PR locked res"]);
	    $result = $prid2result{$procid};	
	    delete $prid2result{$procid};
	}
	print STDERR Data::Dumper->Dump(["after wait","$callback('$result')"]);
	print STDOUT qq|$callback('$result')|;
    } else {
	print STDERR Data::Dumper->Dump(["no wait"]);
	print STDOUT qq|{"msg":"Added command"}\n\n|;
    }

} #process_request

#
# Run by a threat that constantly polls for commands.
#
sub _poll_commands {
    while(1) {
        print STDERR Data::Dumper->Dump( ["StartLoop"] );
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
    print STDERR Data::Dumper->Dump( ["PC"] );
    _connect_db();
    print STDERR Data::Dumper->Dump( ["Reconnect"] );
    
    my $root = GServ::AppProvider::fetch_root();
    print STDERR Data::Dumper->Dump( [$command,$root] );
    my $ret  = $root->process_command( $command );

    #
    # Send return value back to the caller if its waiting for it.
    #
    print STDERR Data::Dumper->Dump( ["about to return and lock",\%prid2wait] );
    lock( %prid2wait );
    {
        print STDERR Data::Dumper->Dump( ["Locking prid2res",\%prid2result] );
        lock( %prid2result );
        $prid2result{$procid} = to_json($ret);
    }
    delete $prid2wait{$procid};
    print STDERR Data::Dumper->Dump( ["broadcasting",\%prid2wait] );
    cond_broadcast( %prid2wait );

} #_process_command

sub _connect_db {
    GServ::ObjIO::database( @DBCONNECT );   
} #_connect_db

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
