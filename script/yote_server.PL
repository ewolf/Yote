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
use feature 'say';

use Carp;
use Config::Simple;
use FindBin qw/\$Bin/;

use Yote::WebAppServer;
use Yote::SQLiteIO;

use lib "\$Bin/../lib";


\$SIG{ __DIE__ } = sub { Carp::confess( \@_ ) };

my \$pidfile = "$base/yote.pid";

my \$s = new Yote::WebAppServer;

\$SIG{TERM} = sub { 
    \$s->shutdown();
    print STDERR "Shutting down due to term\n";
    unlink( \$pidfile );
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

while( \@ARGV ) {
    my \$first = shift \@ARGV;
    if(\$first eq '--shutdown') {
        if( -e \$pidfile ) {
            my \$pid = `cat \$pidfile`;
            \$pid =~ s/[\\n\\r]+\$//i;
            my \$is_pid =  `ps ax | egrep "^\\s\*\$pid\\s+" | grep yote_server`;
            if( \$is_pid ) {
                print STDERR Data::Dumper->Dump( ["shutting down yote server pid \$pid"] );
                `kill \$pid`;
            }
            unlink( \$pidfile );
        }
        exit;
    }
    elsif( \$first eq '--restart' ) {
	#
	# kill any old servers hanging around
	#
	if( -e \$pidfile ) {
            my \$pid = `cat \$pidfile`;
            \$pid =~ s/[\\n\\r]+\$//i;
            my \$is_pid =  `ps ax | egrep "^\\s\*\$pid\\s+" | grep yote_server`;
            if( \$is_pid ) {
                print STDERR Data::Dumper->Dump( ["shutting down yote server pid \$pid"] );
                `kill \$pid`;
            }
	    unlink( \$pidfile );
	    sleep(2);
	}
	last;
    }
    elsif( \$first =~ /^--([^=]+)=(.*)/ ) {
	\$config{\$1} = \$2;
    }
    elsif( \$first =~ /^-([^-].*)/ ) {
	\$config{\$1} = shift \@ARGV;
    }
    else {
	say "yote_server <options>\n".join( "\n\t*", ('--shutdown : stops yote server', '--restart : restarts yote server',
						      '--port=<port> : assigns the yote server to run on specified port',
						      '--datastore=<datastore package name> : use data store other than sqlite',
						      '--sqlitefile=<filename> : specify different sqlite file' ) );
	exit 0;
    }
} #while args

#
# Check to make sure no processes are still hanging around.
#
if( -e \$pidfile ) {
    open( IN, "<\$pidfile" );
    my \$pid = <IN>; 
    chomp( \$pid );

    my( \@haspid ) = `ps -p \$pid`;
    my \$haspid = grep { \$_ =~ /\\b\$pid\\b/ } \@haspid;
    if( \$haspid ) {
	print STDERR "Process \$pid still alive. Unable to start yote server\n";
	exit 1;
    }
}

#
# Normal start
#
`echo \$\$ > \$pidfile`;

\$s->start_server( \%config );

END

__END__

