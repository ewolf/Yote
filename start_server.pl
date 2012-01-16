#!/usr/bin/env perl

use strict;

use Yote::WebAppServer;

my $s= new GServ::WebAppServer;
$s->start_server( datastore => 'Yote::MysqlIO',
		  database  => 'sg',
		  port      => 8008 );
