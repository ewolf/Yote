#!/usr/bin/env perl

use strict;

use Yote::WebAppServer;

my $s= new Yote::WebAppServer;
$s->start_server( datastore => 'Yote::MysqlIO',
		  database  => 'sg',
		  port      => 8008 );
