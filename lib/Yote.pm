package Yote;

################################################################################################
# This package is used by yote_server to parse command line arguments, read yote configuration #
# and launch the server.								       #
################################################################################################


# note : forks and forks::shared should be used before any use strict
use forks;
use forks::shared;

use strict;
use warnings;

use vars qw($VERSION);

$VERSION = '0.1023';

use Carp;
use File::Path;

use Yote::ConfigData;
use Yote::ObjProvider;
use Yote::WebAppServer;


##################
# Public Methods #
##################

sub get_args {

    my %params = ref( $_[0] ) ? %{ $_[0] } : @_;
    
    my $allow_unknown = $params{ allow_unknowns };
    my $allow_multiple_commands = $params{ allow_multiple_commands };

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
	E  => 'engine_port',
	g  => 'generate',
	c  => 'show_config',
	f  => 'profile',
	h  => 'help',
	'?' => 'help',
	H  => 'host',
	P  => 'password',
	p  => 'port',
	R  => 'reset_password',
	A  => 'smtp_auth',
	D  => 'smtp_authdomain',
	N  => 'smtp_auth_encoded',
	I  => 'smtp_authid',
	w  => 'smtp_authpwd',
	T  => 'smtp_TLS_allowed',
	q  => 'smtp_TLS_required',
	s  => 'store',
	u  => 'user',
	r  => 'yote_root',
	t  => 'threads',
	);
    my %noval = (  #arguments that do not take a value
		   help			=> 1,
		   generate		=> 1,
		   show_config		=> 1,
		   reset_password	=> 1,
		   profile              => 1,
	);
    my %argnames = map { $_ => 1 } values %argmap;

    my %required = map { $_ => 1 } qw/engine store yote_root root_account root_password port threads smtp_auth/;

    # ---------  run variables  -----------------

    my %config;
    my $cmd;
    my @cmds;

    # ---------  get command line arguments ---------
    while ( @ARGV ) {
	my $arg = shift @ARGV;

	if ( $arg =~ /^--([^=]*)(=(.*))?/ ) {
	    _soft_exit( "Unknown argument '$arg'" ) unless $argnames{ $1 } || $allow_unknown;
	    $config{ $1 } = $noval{ $1 } ? 1 : $3; 
	} elsif ( $arg =~ /^-(.*)/ ) {
	    _soft_exit( "Unknown argument '$arg'" ) unless $argmap{ $1 } || $allow_unknown;
	    $config{ $argmap{ $1 } } = $noval{ $argmap{ $1 } } ? 1 : shift @ARGV;
	} else {
	    _soft_exit( "Unknown command '$arg'" ) unless $commands{ lc($arg) } || $allow_unknown || $allow_multiple_commands;
	    _soft_exit( "Only takes one command argument" ) if $cmd && ! $allow_multiple_commands;
	    $cmd = $arg;
	    push @cmds, $cmd;
	}
    } # each argument

    # --------- find yote root directory and configuration file ---------
    my $yote_root_dir = $config{ yote_root } || Yote::ConfigData->config( 'yote_root' );
    $config{ yote_root } = $yote_root_dir;
    $ENV{YOTE_ROOT} = $yote_root_dir;

    if( $config{ help } ) {
	_soft_exit();
    }

    _log( "using root directory '$yote_root_dir'" );

    _log( "Looking for '$yote_root_dir/yote.conf'" );

    if( $config{ show_config }  ) {
	my $loaded_config = _load_config( $yote_root_dir );
	print "Yote configuration :\n " . join( "\n ", map { "$_ : $loaded_config->{ $_ }" } keys %$loaded_config ) . "\n";
	exit( 0 );
    }
    elsif( $config{ generate } ) {
	_log( "Generating new configuration file" );
	my $newconfig = _create_configuration( $yote_root_dir, _load_config( $yote_root_dir ) );
	for my $key ( keys %$newconfig ) {
	    $config{ $key } ||= $newconfig->{ $key };
	}	
    }
    elsif( $config{ reset_password } ) {
	%config = %{ _reset_root_password( $yote_root_dir, _load_config( $yote_root_dir ) ) };
	exit( 0 );
    }
    elsif ( -r "$yote_root_dir/yote.conf" ) {
	my $loaded_config = _load_config( $yote_root_dir );
	for my $key ( keys %$loaded_config ) {
	    $config{ lc( $key ) } ||= $loaded_config->{ $key };
	}
	if( grep { ! defined( $config{ $_ } ) } keys %required ) {
	    _log( "The configuration file is insufficient to run yote. Asking user to generate a new one.\n" );
	    my $newconfig = _create_configuration( $yote_root_dir );
	    for my $key ( keys %$newconfig ) {
		$config{ $key } ||= $newconfig->{ $key };
	    }
	}

    } # reading in yote.conf file
    else {
	_log( "No configuration file exists. Asking user to get values for one.\n" );
	my $newconfig = _create_configuration( $yote_root_dir );
	for my $key ( keys %$newconfig ) {
	    $config{ $key } ||= $newconfig->{ $key };
	}
    } #had to write first config file

    $cmd ||= 'start';

    _log( "Returning arguments" );

    return { config => \%config, command => $cmd, commands => \@cmds };
} #get_args

sub run {
    my %config = @_;

    _log( "Running" );

    my $yote_root_dir = $config{ yote_root };

    push( @INC, "$yote_root_dir/lib" );

    my $s = Yote::WebAppServer->new;

    my $start_time = localtime();
    _log( "Starting Server at $start_time" );
    my $args = Data::Dumper->Dump([\%config]);
    _log( $args );

    $s->start_server( %config );

} #run

#
# Convenience method to return the Yote::YoteRoot singleton, connected to the db as outlined by
# the config file.
#
# Warning : do not do any write operations while a Yote server is running. This could cause havoc 
#           if that server is also doing write operations.
#
sub fetch_root {
    my $args = get_args();
    my $config = $args->{ config };
    Yote::ObjProvider::init( $config );
    Data::Dumper->Dump([ $config ]);
    require Yote::YoteRoot;
    return Yote::YoteRoot::fetch_root();
} #fetch_root

###################
# Private Methods #
###################

sub _print_use {
    print 'Usage : yote_server --engine=sqlite|mongo|mysql
                    --engine_port=port-mongo-or-mysql-use
                    --profile
                    --generate
                    --help
                    --host=mongo-or-mysql-host
                    --show_config
                    --password=engine-password 
                    --port=yote-server-port
                    --reset_password
                    --store=filename|mongo-db|mysq-db
                    --threads=number-of-server-processes
                    --user=engine-username 
                    --yote_root=yote-root-directory
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
    print STDERR "$msg : Exiting\n" if $msg;
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
    my( $yote_root_dir, $current_config ) = @_;

    my $newconfig = _get_configuration( $yote_root_dir, $current_config );
    open( my $OUT, '>', "$yote_root_dir/yote.conf" ) or die $@;
    print $OUT "\#\n# Yote Configuration File\n#\n\n".join("\n",map { "$_ = $newconfig->{$_}" } grep { defined($newconfig->{$_}) } keys %$newconfig )."\n\n";
    close( $OUT );
    return $newconfig;

} #_create_configuration

sub _reset_root_password {
    my( $yote_root_dir, $config ) = @_;

    $config->{ root_password } = Yote::ObjProvider::encrypt_pass( _ask( "Root Account Password" ), $config->{ root_account } );

    open( my $OUT, '>', "$yote_root_dir/yote.conf" ) or die $@;
    print $OUT "\#\n# Yote Configuration File\n#\n\n".join("\n",map { "$_ = $config->{$_}" } grep { $config->{$_} } keys %$config )."\n\n";
    close( $OUT );
    return $config;    

} #_reset_root_password

sub _get_configuration {
    my( $yote_root_dir, $current_config ) = @_;
    $current_config ||= {};

    my %newconfig;

    my $engine = _ask( 'This is the first time yote is being run and must be set up now.
 The first decision as to what data store to use.
 mongo db is the fastest, but sqlite will always work.',
		       [ 'sqlite', 'mongo', 'mysql' ], $current_config->{ engine } || 'sqlite' );
    $newconfig{ engine } = $engine;

    if ( $engine eq 'sqlite' ) {
	my $done;
	until( $done ) {
	    my( $dir, $store ) = ( _ask( "sqlite filename", undef, $current_config->{ store } ||  'yote.sqlite' ) =~ /(.*\/)?([^\/]+)$/ );
	    if( $store ) {
		if( $dir && substr( $dir, 0, 1 ) eq '/' ) {
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
	$newconfig{ store }       = _ask( "MongoDB database", undef, $current_config->{ store }       || 'yote' );
	$newconfig{ host }        = _ask( "MongoDB host",     undef, $current_config->{ host }        || 'localhost' );
	$newconfig{ engine_port } = _ask( "MongoDB port",     undef, $current_config->{ engine_port } || 27017 );
	$newconfig{ user }        = _ask( "MongoDB user acccount name", undef, $current_config->{ user } );
	if ( $newconfig{ user } ) {
	    $newconfig{ password } = _ask( "MongoDB user acccount name", undef, $current_config->{ password } );
	}
    }
    elsif ( lc($engine) eq 'mysql' ) {
	$newconfig{ store }       = _ask( "MysqlDB database", undef, $current_config->{ store }       || 'yote' );
	$newconfig{ host }        = _ask( "MysqlDB host",     undef, $current_config->{ host }        || 'localhost' );
	$newconfig{ engine_port } = _ask( "MysqlDB port",     undef, $current_config->{ engine_port } || 27017 );
	$newconfig{ user }        = _ask( "MysqlDB user acccount name", undef, $current_config->{ user } );
	if ( $newconfig{ user } ) {
	    $newconfig{ password } = _ask( "MysqlDB user acccount name", undef, $current_config->{ password } );
	}
    }

    $newconfig{ smtp_smtp }  = _ask( "SMPT Host", undef, $current_config->{ smtp_smtp } || 'localhost' );
    $newconfig{ smtp_port }  = _ask( "SMPT Port", undef, $current_config->{ smtp_port } || 25 );
    $newconfig{ smtp_auth }  = _ask( "SMPT Authentication Method", ['LOGIN','PLAIN','CRAM-MD5','NTLM'], $current_config->{ smtp_auth } || 'PLAIN' );
    if( $newconfig{ smtp_auth } eq 'NTLM' ) {
	$newconfig{ smtp_authdomain }  = _ask( "NTML Auth Domain", $current_config->{ smtp_authdomain } );
    }
    elsif( $newconfig{ smtp_auth } eq 'LOGIN' ) {
	$newconfig{ smtp_auth_encoded }  = _ask( "Should the LOGIN protocoll assume authid and authpwd are already base64 encoded?", ['Yes','No' ],  $current_config->{ smtp_auth_encoded } ? 'Yes' : 'No' );
	$newconfig{ smtp_auth_encoded } = $newconfig{ smtp_auth_encoded } ? 1 : 0;
    }
    if( $newconfig{ smtp_auth } eq 'PLAIN' ) {
	$newconfig{ smtp_auth } = '';
    }
    else {
	$newconfig{ smtp_authid }  = _ask( "Auth ID", undef, $current_config->{ smtp_authid } );
	$newconfig{ smtp_authpwd } = _ask( "Auth Password", undef, $current_config->{ smtp_authpwd } );
    }
    $newconfig{ smtp_TLS_allowed } = _ask( "Should TLS ( SSL encrypted connection ) be used ", ['Yes','No'], $current_config->{ smtp_TLS_allowed } ? 'Yes' : 'No' );
    $newconfig{ smtp_TLS_allowed } = $newconfig{ smtp_TLS_allowed } eq 'Yes' ? 1 : 0;
    $newconfig{ smtp_TLS_required } = _ask( "Must TLS ( SSL encrypted connection ) be used", ['Yes','No'], $current_config->{ smtp_TLS_required } ? 'Yes' : 'No' );
    $newconfig{ smtp_TLS_required } = $newconfig{ smtp_TLS_required } eq 'Yes' ? 1 : 0;


    $newconfig{ port } = _ask( "Port to run yote server on?",     undef, $current_config->{ port }    || 80 );
    $newconfig{ threads } = _ask( "Number of server processes :", undef, $current_config->{ threads } || 4 );

    # this is as secure as the file permissions of the config file, and as secure as the data store is itself.
    $newconfig{ root_account  } = _ask( "Root Account name", undef, $current_config->{ root_account} || 'root' );
    $newconfig{ root_password } = Yote::ObjProvider::encrypt_pass( _ask( "Root Account Password", undef,  ),
								   $newconfig{ root_account } );

    return \%newconfig;
} #_get_configuration


sub _load_config {
    my $yote_root_dir = shift;

    my %config;
    if( -r "$yote_root_dir/yote.conf" ) {
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
    }
    return \%config;
} #_load_config

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

* container objects exist in a graph structure

* multi-threaded request handling

* Object fields and connections are contents are free form and require no schema definition

=back

Yote on the client is a javascript library that provides

=over 4

* RPC bound yote objects

* web controls that bind to the yote objects

* web controls for account management

* web widgets for use with yote objects

=back

=head1 DESCRIPTION

The purpose of Yote to be able to develop rapidly, flexbily and 
fluidly. Yote stores a graph of interconnected container objects.
Each of these can be connected to any other, and each may have 
properties attached to them. No schema is needed to describe how
objects are connected or what properties they contain.

There is an organization to this object graph, however; all objects
that are 'live' can trace back to the root of the graph. This root
contains a collection of user logins and application objects. It 
provides methods for creating these login objects, which, since they are
Yote objects, can have arbitrary properties attached to them. The
application objects are singleton Yote objects are are accessed via 
the fetch_app_by_class method attached to the root.

I wrote Yote because I wanted to write object oriented applications,
particulally web applications and prototypes, in a ferenic ADHD style. I did
want want to have to set up schemas, and then make changes to them as the 
application changed.


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

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
