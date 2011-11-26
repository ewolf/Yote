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

sub start_server {
    my( $self, @args ) = @_;
    my $args = scalar(@args) == 1 ? $args[0] : { @args };
    $args->{port} ||= 8008;
    my $db = $args->{database} || 'sg';

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
    my $self = shift;

    my $reqstr;
    while(<STDIN>) {
	$reqstr .= $_;
	last if $_ =~ /^[\n\r]+$/s;
    }
    my $parse_params = HTTP::Request::Params->new( { req => $reqstr } );
    my $params       = $parse_params->params;
    my $command = from_json( MIME::Base64::decode($params->{m}) );
    $command->{oi} = $self->{server}{peeraddr}; #origin ip
    share( $command );

    my $wait = $command->{w};
    {
	lock( %prid2wait );
	$prid2wait{$$} = $wait;
    }
    
    #
    # Queue up the command for processing in a separate thread.
    #
    {
	lock( @commands );
	push( @commands, [$command, $$] );
	cond_broadcast( @commands );
    }


    print STDERR Data::Dumper->Dump(["WAIT $wait"]);
    if( $wait ) {
	while( $prid2wait{$$} ) {
	    lock( %prid2wait );
	    print STDERR Data::Dumper->Dump(["PR $$ locked wait, ready to cond wait wait"]);
	    cond_wait( %prid2wait );
	}
	my $result;
	{
	    print STDERR Data::Dumper->Dump(["PR lock res",%prid2result]);
	    lock( %prid2result );
	    print STDERR Data::Dumper->Dump(["PR locked res"]);
	    $result = $prid2result{$$};	
	    delete $prid2result{$$};
	}
	print STDERR Data::Dumper->Dump(["after wait",$command,$result]);
	print STDOUT $result;
    } else {
	print STDOUT qq|{"msg":"Added command"}\n\n|;
    }

} #process_request

#
# Run by a threat that constantly polls for commands.
#
sub _poll_commands {
    while(1) {
	print STDERR Data::Dumper->Dump(["polling loop"]);
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

    my $root = GServ::AppProvider::fetch_root();
    my $ret  = $root->process_command( $command );

    #
    # Send return value back to the caller if its waiting for it.
    #
    lock( %prid2wait );
    {
	print STDERR Data::Dumper->Dump(["_PR lock res"]);
	lock( %prid2result );
	print STDERR Data::Dumper->Dump(["_PR locked res"]);
	$prid2result{$procid} = to_json($ret);
	print STDERR Data::Dumper->Dump(["_PR set val"]);
    }
    print STDERR Data::Dumper->Dump(['cond signal for wait']);
    undef $prid2wait{$procid};
    print STDERR Data::Dumper->Dump(["_PC releasing wait"]);
    cond_signal( %prid2wait );
    print STDERR Data::Dumper->Dump(["_PC released wait"]);

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
