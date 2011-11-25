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

my( @commands );#  : shared;
share( @commands );

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
    share( $wait );

    my $result = '';
    share( $result );

    #
    # Queue up the command for processing in a separate thread.
    #
    {
	lock( @commands );
	push( @commands, [$command, $wait, $result] );
	cond_signal( @commands );
    }
    print STDERR Data::Dumper->Dump(["WAIT $wait"]);
    if( $wait ) {
	print STDERR Data::Dumper->Dump(["PR to lock wait"]);
	lock( $wait );
	print STDERR Data::Dumper->Dump(["PR locked wait, ready to cond wait wait"]);
	cond_wait( $wait );
    print STDERR Data::Dumper->Dump(["after wait",$command]);
	print STDOUT to_json( $result );
#	print STDOUT qq|{"msg":"waited for command"}\n\n|;
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
    print STDERR Data::Dumper->Dump(["_proc",$req]);
    my( $command, $wait, $result ) = @$req;

    my $root = GServ::AppProvider::fetch_root();
    print STDERR Data::Dumper->Dump(["process $$ command start '$wait'"]);
    my $ret  = $root->process_command( $command );
    $result = $ret;
    print STDERR Data::Dumper->Dump(["process $$ command returned. command now ($wait)",$command,$@,$!]);

    #
    # Send return value back to the caller if its waiting for it.
    #
    if( $wait ) {
	print STDERR Data::Dumper->Dump(['to lock wait']);
        lock( $wait );
	print STDERR Data::Dumper->Dump(['locked wait']);
        cond_signal( $wait );
	print STDERR Data::Dumper->Dump([' wait signal']);
    }
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
