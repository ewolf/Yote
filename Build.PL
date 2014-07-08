use strict;
use warnings;
use File::Copy;
use Module::Build;

use strict;
use warnings;

# check to find the root directory for yote using a list of common candidates
my( $yote_root_parent ) = grep { -e $_ && -r $_ && -w $_ } ( '/opt',
							     '/var',
							     '/usr/local',
							     $ENV{HOME},
							     '.'
							   );

die "Unable to write yote root directory" unless -w $yote_root_parent;
my $yote_root = "$yote_root_parent/yote";

mkdir $yote_root unless -d $yote_root;

die "Unable to create root directory" unless -w $yote_root;

mkdir "$yote_root/holding";
mkdir "$yote_root/html";
mkdir "$yote_root/html/templates";
mkdir "$yote_root/html/uploads";
mkdir "$yote_root/html/DEFAULT";
mkdir "$yote_root/data";
mkdir "$yote_root/lib";
mkdir "$yote_root/log";
mkdir "$yote_root/daemon";

# fill the root directory
sub copy_dir {
    my( $dir, $dest, $overwrite ) = @_;
    mkdir "$dest" unless -d "$dest";
    opendir( my $DIN, $dir );
    while( my $fn = readdir $DIN ) {
	next if $fn =~ /^\.+$/;
	if( -d "$dir/$fn" ) {
	    copy_dir( "$dir/$fn", "$dest/$fn", $overwrite );
	}
	elsif( ! -e "$dest/$fn" || $overwrite ) {
	    copy( "$dir/$fn", "$dest/$fn" );
	}
    }
} #copy_dir
copy_dir( 'yote_root', $yote_root );
copy_dir( 'yote_root/html/yote', "$yote_root/html/yote", 1 );


my $builder = Module::Build->new(
    add_to_cleanup      => [ 'Yote-*' ],
    build_requires => {
        'Test::More' => 0,
	'Test::Pod'  => 0,
    },
    create_makefile_pl => 'traditional',
    dist_author        => q{Eric Wolf (coyocanid@gmail.com)},
    dist_version_from  => 'lib/Yote.pm',
    license            => 'perl',
    module_name        => 'Yote',
    release_status     => 'stable',
    script_files       => [ 'bin/yote_server' ],
    test_files         => [ 't/sqlite.t', 't/docs.t', 't/pod-coverage.t', ],
    recommends         => {
	'Digest::HMAC_MD5' => 1,
	'Authen::NTLM'     => 1,
	'MongoDB'          => 1,
	'DBD::mysql'       => 1,
    },
    requires => {
	'perl'                  => 'v5.12',
	'Aspect'                => 1.04,
	'Crypt::Passwd::XS'     => 0.601,
    'Daemon::Daemonize'     => 0.0052,
	'DateTime'              => 0.77,
	'DBD::SQLite'           => 1.35,
	'DBI'                   => 1.625,
	'Email::Valid'          => 0.190,
	'File::UStore'          => 0.12,
	'forks'                 => 0.34,
	'forks::shared'         => 0.34,
	'JavaScript::Minifier'  => '1.11',
	'JSON'                  => 2.53,
	'Mail::Sender'          => 0,
	'MIME::Base64'          => 0,
	'Test::More'            => 0,
	'Test::Pod'             => 0,
	'WeakRef'               => 0.01,
    },
    );

$builder->config_data( 'yote_root' => $yote_root );

$builder->create_build_script();
