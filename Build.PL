#!/usr/bin/env perl

use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Yote',
    license             => 'perl',
    dist_author         => q{Eric Wolf (coyocanid@gmail.com)},
    dist_version_from   => 'lib/Yote.pm',
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
		     'forks'                 => 0,
		     'Config::Simple'        => 4.58,
             'App::Options'          => 1.12,
		     'DBD::mysql'            => 4.014,
		     'DBD::SQLite'           => 1.35,
		     'HTTP::Request::Params' => 1.01,
		     'JSON'                  => 2.22,
		     'MIME::Base64'          => 3.08,
		     'Net::Server::Fork'     => 0.99,
		     'IO::Socket'            => 1.31,
                     'Test::Simple'          => 0.44,
		     'WeakRef'               => 0.01,
    },
    add_to_cleanup      => [ 'Yote-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
