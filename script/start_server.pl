#!/usr/bin/env perl

#
# start_server.pl - this file is meant to be configured by the user.
#                   You don't want to include world readable passwords
#                   so add your own configuration 
#                    (pending a better yote configuration)
#

use strict;

use Yote::WebAppServer;

my $s = new Yote::WebAppServer;

my $use_mysql = 0;

if( $use_mysql ) {
    $s->start_server( datastore => 'Yote::MysqlIO',
		      database  => 'sg',
		      uname     => 'MYSQL USERNAME',
		      pword     => 'MYSQL PASSWORD',
		      port      => 8008 );
} else {
    $s->start_server( datastore  => 'Yote::SQLiteIO',
		      sqlitefile => 'MY/DATABASE/FILE',
		      port      => 8008 );
}

__END__

