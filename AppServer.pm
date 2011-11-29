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

    #make sure this thread has a valid database connectin
    print STDERR Data::Dumper->Dump(['start servier']);
    GServ::ObjIO::database( DBI->connect( "DBI:mysql:$db", $args->{uname}, $args->{password} ) );
    print STDERR Data::Dumper->Dump(['connected db']);

    # fork out for two starting threads
    #   - one a multi forking server and the other an event loop.
    my $thread = threads->new( \&_poll_commands );
    print STDERR Data::Dumper->Dump(['forked thread']);

    $self->run( %$args );
    print STDERR Data::Dumper->Dump(['thread running']);
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
    print STDERR Data::Dumper->Dump(['process req called']);
    my $self = shift;

    my $reqstr;
    while(<STDIN>) {
	$reqstr .= $_;
	last if $_ =~ /^[\n\r]+$/s;
    }
    my $parse_params = HTTP::Request::Params->new( { req => $reqstr } );
    my $params       = $parse_params->params;
    my $callback = $params->{callback};
    print STDERR Data::Dumper->Dump([$params]);
    my $command = from_json( MIME::Base64::decode($params->{m}) );
    $command->{oi} = $self->{server}{peeraddr}; #origin ip

    my $wait = $command->{w};
    my $procid = $$;
    {
	print STDERR Data::Dumper->Dump(["locking waits for process req",$command]);
	lock( %prid2wait );
	$prid2wait{$procid} = $wait;
    }
    print STDERR Data::Dumper->Dump(["locking comands"]);
    #
    # Queue up the command for processing in a separate thread.
    #
    {
	lock( @commands );
	print STDERR Data::Dumper->Dump(["putting cmd on queue"]);
	push( @commands, [$command, $procid] );
	cond_broadcast( @commands );
    }


    print STDERR Data::Dumper->Dump(["WAIT $wait"]);
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
	print STDERR Data::Dumper->Dump(["polling loop $$"]);
        my $cmd;
        {
            lock( @commands );
            $cmd = shift @commands;
        }
	print STDERR Data::Dumper->Dump(["In loop with command $cmd"]);
        if( $cmd ) {
            _process_command( $cmd );
        } 
        unless( @commands ) {
            lock( @commands );
            cond_wait( @commands );
	}
	print STDERR Data::Dumper->Dump(["command count ".scalar(@commands)]);
    }

} #_poll_commands

sub _process_command {
    my $req = shift;

    GServ::ObjIO::database( DBI->connect( "DBI:mysql:$db", $args->{uname}, $args->{password} ) );

    my( $command, $procid ) = @$req;

    my $root = GServ::AppProvider::fetch_root();
    print STDERR Data::Dumper->Dump(["_PC to do command"]);
    my $ret  = $root->process_command( $command );
    print STDERR Data::Dumper->Dump(["_PC done command. obtaining lock"]);

    #
    # Send return value back to the caller if its waiting for it.
    #
    lock( %prid2wait );
    {
	print STDERR Data::Dumper->Dump(["_PC lock res"]);
	lock( %prid2result );
	print STDERR Data::Dumper->Dump(["_PC locked res"]);
	$prid2result{$procid} = to_json($ret);
	print STDERR Data::Dumper->Dump(["_PC set val"]);
    }
    print STDERR Data::Dumper->Dump(['_PC cond signal for wait',\%prid2wait]);
    delete $prid2wait{$procid};
    print STDERR Data::Dumper->Dump(["_PC releasing wait"]);    
    cond_signal( %prid2wait );
    print STDERR Data::Dumper->Dump(["_PC released wait $@",\%prid2wait]);

} #_process_command


1

__END__

=head1 NAME

GServ::AppServer - is a library used for creating prototype applications for the web.

=head1 SYNOPSIS

    use GServ::AppServer;
    
    my $server = new GServ::AppServer;
    $server->init_server( database => 'database to use' ); 
    $server->start_server( port => 8008, database => 'database to use' );
    

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
