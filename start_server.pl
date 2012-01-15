#!/usr/bin/env perl

use strict;

use GServ::AppServer;

my $s= new GServ::AppServer;
$s->start_server( datastore => 'GServ::MysqlIO',
		  database  => 'sg',
		  port      => 8008 );
