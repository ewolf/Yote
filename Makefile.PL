
use Module::Build;

use File::Path qw/mkpath/;

my $class = 'Module::Build';

my $build = $class->new( 
    dist_author   => 'Eric Wolf (coyocanid@gmail.com)',
    dist_abstract => 'Web App Server w/ autopersistant objects',
    license       => 'perl',

    dist_version_from => 'lib/Yote.pm',
    module_name   => 'Yote',

    PL_files => {
	'script/yote_server.PL' => 'script/yote_server',
    },

    script_files  => [ 'script/yote_server' ],
 
    requires      => {
        # for the installer and testing
        'Config::Simple'        => 4.58,  
        'File::Copy'            => 2.18,
        'File::Path'            => '2.08_01',
        'File::chmod'           => 0.32,
	'File::Pid'             => 0,
        
        'DBD::SQLite'           => 1.35,
        'JSON'                  => 2.22,
        'MIME::Base64'          => 3.08,
        'Net::Server::HTTP'     => 0.99,
        'Test::Simple'          => 0.44,
        'WeakRef'               => 0.01,
        'forks'                 => 0.34,
        'DBI'                   => 0,
        'Crypt::Passwd'         => 0,
        'Email::Valid'          => 0,
        'MIME::Lite'            => 0,
        'MIME::Base64'          => 0,
    },
);

$build->create_build_script();



