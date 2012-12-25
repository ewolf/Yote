#!/usr/bin/env perl

use 5.006;
use strict;
use warnings;
use File::Copy;
use Module::Build;

# check to see where the database can be kept
my $yote_base_dir = '/usr/local/yote';
unless( -w '/usr/local' ) {
    $yote_base_dir = "$ENV{HOME}/.yote";
}
mkdir $yote_base_dir unless -d $yote_base_dir;
sub copy_dir {
    my( $dir, $dest ) = @_;
    mkdir "$dest" unless -d "$dest";
    opendir( my $DIN, $dir );
    while( my $fn = readdir $DIN ) {
	next if $fn =~ /^\.+$/;
	if( -d "$dir/$fn" ) {
	    copy_dir( "$dir/$fn", "$dest/$fn" );
	} 
	else {	    
	    copy( "$dir/$fn", "$dest/$fn" );
	}
    }
}

copy_dir( 'yote_root', $yote_base_dir );

my $yote_var_dir = '/var/yote';
unless( -w '/var/' ) {
    $yote_var_dir = "$ENV{HOME}/.yote";
}
mkdir $yote_var_dir unless -d $yote_var_dir;

my $yote_run_dir = '/var/run';
unless( -w $yote_run_dir ) {
    $yote_run_dir = "$ENV{HOME}/.yote";
    mkdir $yote_run_dir unless -d $yote_run_dir;
}

my $builder = Module::Build->new(
    add_to_cleanup      => [ 'Yote-*' ],
    build_requires => {
        'Test::More' => 0,
    },
    create_makefile_pl => 'traditional',
    dist_author        => q{Eric Wolf (coyocanid@gmail.com)},
    dist_version_from  => 'lib/Yote.pm',
    license            => 'perl',
    module_name        => 'Yote',
    release_status     => 'alpha',
    script_files       => [ 'bin/yote_server' ],
    requires => {
	'Crypt::Passwd::XS'     => 0.601,
	'forks'                 => 0.34,
	'DateTime'              => 0.77,
	'DBD::SQLite'           => 1.35,
	'DBI'                   => 0,
	'Email::Valid'          => 0.190,
	'File::UStore'          => 0.12,
	'JSON'                  => 0,
	'Mail::Sender'          => 0,
	'MIME::Lite'            => 3.029,
	'Net::Server::HTTP'     => 0,
	'WeakRef'               => 0.01,
    },
    );

$builder->config_data( 'yote_var_dir' => $yote_var_dir );
$builder->config_data( 'yote_run_dir' => $yote_run_dir );
$builder->config_data( 'yote_base_dir' => $yote_base_dir );
$builder->config_data( 'port'         => 8008 );

$builder->create_build_script();
