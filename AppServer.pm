package GServ::AppServer;

#
# Proof of concept server with main loop.
#
use strict;

use forks;
use forks::shared;

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
    GServ::ObjIO::database( DBI->connect( "DBI:mysql:$db", $args->{uname}, $args->{password} ) );

    # fork out for two starting threads
    #   - one a multi forking server and the other an event loop.
    my $thread = threads->new( \&_poll_commands );

    $self->run( %$args );
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
#
# Commands have the following structure :
#   * a - app
#   * c - cmd
#   * data - data
#   * wait - if true, waits for command to be processed before returning
#
#
# This ads a command to the list of commands. If 
#
sub process_request {
    my $self = shift;
    eval {
        local $SIG{'ALRM'} = sub { die "Timed Out!\n" };
        my $timeout = 6; # give the user 6 seconds to type some lines

        my $previous_alarm = alarm($timeout);

        my( $req, $input );

        while (<STDIN>) {
            $input .= $_;
            alarm($timeout);
            if( $input =~ /\n(\S+)\n\n$/s ) {
                $req = $1;
                last;
            }
        }
        my $command = from_json( MIME::Base64::decode($req) );
	$command->{oi} = $self->{server}{peeraddr}; #origin ip
        share( $command );


        my $wait = $command->{wait};
        share( $wait );

        #
        # Queue up the command for processing in a separate thread.
        #
        {
            lock( @commands );
            push( @commands, [$command, $wait] );
            cond_signal( @commands );
        }
        if( $wait ) {
            lock( $wait );
            cond_wait( $wait );
            print STDOUT qq|{"msg":"waited for command"}\n\n|;
        } else {
            print STDOUT qq|{"msg":"Added command"}\n\n|;
        }
        alarm($previous_alarm);
    };
    if( $@ =~ /timed out/i ) {
        print STDOUT qq|{"err":"timed out"}\n\n|;
        return;
    } elsif( $@ ) {
        print STDOUT to_json( { err => $@ } )."\n\n";
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

    my( $command, $wait ) = @$req;

    my $root = GServ::AppProvider::fetch_root();
    my $ret  = $root->process_command( $command );
    $command->{result} = $ret;

    #
    # Send return value back to the caller if its waiting for it.
    #
    if( $wait ) {
        lock( $wait );
        cond_signal( $wait );
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
