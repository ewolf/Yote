package Yote;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.0993';

use Carp;
use File::Path;

use Yote::ConfigData;
use Yote::ObjProvider;
use Yote::SQLiteIO;
use Yote::WebAppServer;

sub _print_use {
    print '
Usage :
yote_server --engine=sqlite|mongo|mysql --user=engine-username --password=engine-password \\
            --store=filename|mongo-db|mysq-db --host=mongo-or-mysql-host --engine_port=port-mongo-or-mysql-use \\
            --port=yote-server-port \\
            START|STOP|RESTART
';
    return;
}

sub _log {
    my $foo = shift;
    print STDERR "$foo\n";
    return;
}

sub _soft_exit {
    my $msg = shift;
    print STDERR "$msg : Exiting\n";
    _print_use();
    exit(0);
}

sub _ask {
    my( $question, $allowed, $default ) = @_;
    my %valmap;
    if( $allowed ) {
	%valmap = map { (1 + $_ ) => $allowed->[$_] } ( 0 .. $#$allowed );
	for my $all (@$allowed) { $valmap{ lc( $all ) } = $all; }
    }

    while( 1 ) {
	if( $allowed ) {
	    print "$question : possible values ( ".join(',',map { (1 + $_ ) .") $allowed->[$_]".($default eq $allowed->[$_] ? '*' : '') } ( 0 .. $#$allowed )).") ? ";
	} elsif( $default ) {
	    print "$question : [ $default ]?";
	} else {
	    print "$question : ";
	}
	my $ans = <STDIN>;
	$ans =~ s/[\n\r]+$//;
	if( $allowed && $valmap{ lc($ans) } ) {
	    return $valmap{ lc($ans) }
	}
	elsif( $ans !~ /\S/ && $default ) {
	    return $default;
	}
	elsif( ! $allowed ) {
	    return $ans;
	}
	print "'$ans' not a valid value. Try again\n";
    }
} #_ask

sub _create_configuration {
    my $yote_root_dir = shift;

    my $newconfig = _get_configuration( $yote_root_dir );

    open( my $OUT, '>', "$yote_root_dir/yote.conf" ) or die $@;
    print $OUT "\#\n# Yote Configuration File\n#\n\n".join("\n",map { "$_ = $newconfig->{$_}" } grep { $newconfig->{$_} } keys %$newconfig )."\n\n";
    close( $OUT );
    return $newconfig;

} #_create_configuration

sub _get_configuration {
    my $yote_root_dir = shift;

    my %newconfig;

    my $engine = _ask( 'This is the first time yote is being run and must be set up now.
The first decision as to what data store to use.
mongo db is the fastest, but sqlite will always work.',
		      [ 'sqlite', 'mongo', 'mysql' ], 'sqlite' );
    $newconfig{ engine } = $engine;

    if ( $engine eq 'sqlite' ) {
	my $done;
	until( $done ) {
	    my( $dir, $store ) = ( _ask( "sqlite filename", undef, 'yote.sqlite' ) =~ /(.*\/)?([^\/]+)$/ );
	    print "$dir, $store\n";
	    if( $store ) {
		if( substr( $dir, 0, 1 ) eq '/' ) {
		    if( -d $dir && -w $dir ) {
			$done = 1;
			$newconfig{ store } = "$dir$store";
		    }
		}
		elsif( $dir ) {
		    my $full_store = "$yote_root_dir/$dir";
		    mkpath( $full_store );
		    $newconfig{ store } = "$full_store/$store";
		    $done = 1;
		}
		else {
		    $newconfig{ store } = "$yote_root_dir/data/$store";
		    $done = 1;
		}
	    }
	}
    }
    elsif ( lc($engine) eq 'mongo' ) {
	$newconfig{ store }       = _ask( "MongoDB database", undef, 'yote' );
	$newconfig{ host }        = _ask( "MongoDB host", undef, 'localhost' );
	$newconfig{ engine_port } = _ask( "MongoDB port", undef, 27017 );
	$newconfig{ user }        = _ask( "MongoDB user acccount name" );
	if ( $newconfig{ user } ) {
	    $newconfig{ password } = _ask( "MongoDB user acccount name" );
	}
    }
    elsif ( lc($engine) eq 'mysql' ) {
	$newconfig{ store }       = _ask( "MysqlDB database", undef, 'yote' );
	$newconfig{ host }        = _ask( "MysqlDB host", undef, 'localhost' );
	$newconfig{ engine_port } = _ask( "MysqlDB port", undef, 27017 );
	$newconfig{ user }        = _ask( "MysqlDB user acccount name" );
	if ( $newconfig{ user } ) {
	    $newconfig{ password } = _ask( "MysqlDB user acccount name" );
	}
    }

    $newconfig{ port } = _ask( "Port to run yote server on?", undef, 80 );

    # this is as secure as the file permissions of the config file, and as secure as the data store is itself.
    $newconfig{ root_account  } = _ask( "Root Account name", undef, 'root' );
    $newconfig{ root_password } = Yote::ObjProvider::encrypt_pass( _ask( "Root Account Password" ), $newconfig{ root_account } );

    return \%newconfig;
} #_get_configuration


sub get_args {
    # -------- run data ---------------------------

    my %commands = (
	'start'    => 'start',
	'restart'  => 'restart',
	'stop'     => 'stop',
	'halt'     => 'stop',
	'shutdown' => 'stop',
	);

    my %argmap = (
	e  => 'engine',
	s  => 'store',
	p  => 'port',
	u  => 'user',
	P  => 'password',
	r  => 'root',
	);
    my %argnames = map { $_ => 1 } values %argmap;
    my %required = map { $_ => 1 } qw/engine store yote_root root_account root_password port/;

    # ---------  run variables  -----------------

    my %config;
    my $cmd;

    # ---------  get command line arguments ---------
    while ( @ARGV ) {
	my $arg = shift @ARGV;
	if ( $arg =~ /^--(.*)=(.*)/ ) {
	    _soft_exit( "Unknown argument '$arg'" ) unless $argnames{ $1 };
	    $config{ $1 } = $2;
	} elsif ( $arg =~ /^-(.*)/ ) {
	    _soft_exit( "Unknown argument '$arg'" ) unless $argmap{ $1 };
	    $config{ $1 } = shift @ARGV;
	} else {
	    _soft_exit( "Unknown command '$arg'" ) unless $commands{ lc($arg) };
	    _soft_exit( "Only takes one command argument" ) if $cmd;
	    $cmd = $arg;
	}
    } # each argument

    # --------- find yote root directory and configuration file ---------
    my $yote_root_dir = Yote::ConfigData->config( 'yote_root' );
    $config{ yote_root } = $yote_root_dir;

    _log "using root directory '$yote_root_dir'";

    _log "Looking for '$yote_root_dir/yote.conf'";

    if ( -r "$yote_root_dir/yote.conf" ) {
	open( my $IN, '<', "$yote_root_dir/yote.conf" ) or die $@;
	while ( <$IN> ) {
	    s/\#.*//;
	    next unless /\S/;
	    if ( /\s*(\S+)\s*=\s*(.*)\s*$/ ) {
		$config{ lc( $1 ) } ||= $2;
	    } else {
		chop;
		warn "Bad line in config file : '$_'";
	    }
	}
	close( $IN );
	if( grep { ! $config{ $_ } } keys %required ) {
	    _log "The configuration file is insufficient to run yote. Asking user to generate a new one.\n";
	    my $newconfig = _create_configuration( $yote_root_dir );
	    for my $key ( keys %$newconfig ) {
		$config{ $key } ||= $newconfig->{ $key };
	    }
	}

    } # reading in yote.conf file
    else {
	_log "No configuration file exists. Asking user to get values for one.\n";
	my $newconfig = _create_configuration( $yote_root_dir );
	for my $key ( keys %$newconfig ) {
	    $config{ $key } ||= $newconfig->{ $key };
	}
    } #had to write first config file

    $cmd ||= 'start';

    _log "Returning arguments";

    return { config => \%config, command => $cmd };
} #get_args

sub run {
    my %config = @_;

    _log "Running";

    my $yote_root_dir = $config{ yote_root };

    push( @INC, "$yote_root_dir/lib" );

    my $s = Yote::WebAppServer->new;

    _log "Starting Server";
    my $args = Data::Dumper->Dump([\%config]);
    _log $args;

    $s->start_server( %config );

} #run

1;

__END__

=head1 NAME

Yote - Code server side, use client side.

=head1 SYNOPSIS

$ yote_server start

Yote is a platform that

=over 4

* serves up any number of separate applications

* provides account management

* provides access control for objects and methods

=back

Yote on the server side is a server that is a

=over 4

* schemaless object database with a recursive tree structure

* multi-threaded request queuing server

* single-threaded execution server

=back

Yote on the client is a javascript library that provides

=over 4

* RPC bound yote objects

* web controls that bind to the yote objects

* web controls for account management

=back

=head1 DESCRIPTION

I wrote Yote because I wanted to write object oriented applications,
particulally web applications and prototypes, in a ferenic ADHD style.

I wanted the objects and their data to connect together as
easily as one connects tinker toys together.
I found writing and modifying table schemas, especially for prototypes, is a
drag on the development and testing and I wanted to get rid of that
step once and for all for at least prototype development.

I had chance to use SOAP and XMLHttpdRequest calls. SOAP I found too
slow, and at the time had seen it only for php, jsp and other server
side web languages.

=head1 PUBLIC METHODS

=over 4

=item get_args

Calling this returns an array ref of configuration arguments as  that have been passed in through the @ARGV
array or that are saved in the yote configuration.
If no configuration has been saved, this program prompts the user for configuration values and saves them if able.

=item run( %args )

This method activates starts the Yote server with configuration values that have been passed in. It does not
return until the yote server has shut down.

=back

=head1 BUGS

There are likely bugs to be discovered. This is alpha software.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
