use strict;
use Module::Build;
use File::Copy;
use File::Path;
use File::chmod qw( symchmod lschmod );

my $builder = Module::Build->current;

my $base = $builder->args( 'install_base' ) || '/usr/local/yote';
my $port = $builder->args( 'port' ) || 8008;

mkpath( $base );

my $file = shift @ARGV;
open my $fh, '>', $file or die "Unable to create file : $!";


print $fh <<END;
#!/usr/bin/env perl

#
# start_server.pl - start,stop,restart
#


use strict;

use Carp;
use Config::Simple;

use Yote::WebAppServer;
use Yote::SQLiteIO;
use File::Pid;

push( \@INC, "$base/lib" );

\$SIG{ __DIE__ } = sub { Carp::confess( \@_ ) };

my \$pidfile = File::Pid->new( { file => "$base/yote.pid" } );

my \$s = new Yote::WebAppServer;

\$SIG{TERM} = sub { 
    \$s->shutdown();
    print STDERR "Shutting down due to term\n";
    \$pidfile->remove();
    exit;
};



#
# The order of the config is \@ARGV, \%ENV, ~/.yoterc || ~/.yote/yote.conf || /etc/yote.conf, 
#
my \$sqlitefile = "$base/data/SQLite.yote.db";
my \$webroot = "$base/html";
unless( -e \$sqlitefile ) {
    my \$sqlite = new Yote::SQLiteIO( sqlitefile => \$sqlitefile );
    \$sqlite->ensure_datastore();
}
my( \%config ) = ( port       => $port, 
		   webroot  => \$webroot,
		   datastore  => 'Yote::SQLiteIO', 
		   sqlitefile => \$sqlitefile );

my \$do_start = 1;
while( \@ARGV ) {
    my \$first = shift \@ARGV;
    if(\$first eq '--shutdown') {
	if( \$pidfile->running() ) {
	    \$pidfile->pid->kill();
	}
	\$pidfile->remove();
	\$do_start = 0;
        exit;
    }
    elsif( \$first eq '--version' || \$first eq '-V' ) {
	print "$Yote::VERSION\n";
	exit;
    }
    elsif( \$first eq '--restart' ) {
	#
	# kill any old servers hanging around
	#
	if( \$pidfile->running() ) {
	    \$pidfile->pid->kill();
	}
	\$pidfile->write();
	\$do_start = 0;
	last;
    }
    elsif( \$first =~ /^--([^=]+)=(.*)/ ) {
	\$config{\$1} = \$2;
    }
    elsif( \$first =~ /^-([^-].*)/ ) {
	\$config{\$1} = shift \@ARGV;
    }
    else {
	say "yote_server <options>\\n".join( "\\n\\t*", ('--shutdown : stops yote server', '--restart : restarts yote server',
							'--port=<port> : assigns the yote server to run on specified port',
							'--datastore=<datastore package name> : use data store other than sqlite',
							'--sqlitefile=<filename> : specify different sqlite file' ) );
	exit 0;
    }
} #while args

#
# Check to make sure no processes are still hanging around.
#
if( \$do_start ) {
    if( \$pidfile->running() ) {
        \$pidfile->pid->kill();
    }
}

#
# Normal start
#
\$pidfile->write();

\$s->start_server( \%config );

END

__END__

