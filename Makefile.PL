use Module::Build;

use File::Path qw/mkpath/;

my $class = 'Module::Build';

my $build = $class->new( 
    dist_author   => 'Eric Wolf (coyocanid@gmail.com)',
    dist_abstract => 'Web App Server w/ autopersistant objects',
    license       => 'perl',

    dist_version_from => 'lib/Yote/WebAppServer.pm',
    module_name   => 'Yote',

    PL_files => {
	'script/yote_server.PL' => 'script/yote_server',
    },

    script_files  => [ 'script/yote_server' ],
 
    requires      => {
	'Config::Simple'        => 4.58,
	'App::Options'          => 1.12,
	'DBD::SQLite'           => 1.35,
	'HTTP::Request::Params' => 1.01,
	'JSON'                  => 2.22,
	'MIME::Base64'          => 3.08,
	'Net::Server::Fork'     => 0,
	'IO::Socket'            => 1.31,
	'Test::Simple'          => 0.44,
	'WeakRef'               => 0.01,
	'forks'                 => 0,
	'File:Copy'             => 0,
	'File:Path'             => 0,
	'File:chmod'            => 0,
	'DBI'                   => 0,
    },
);

my $cgi_dir = $build->prompt("What is the location of your cgi-bin directory?");
$build->notes( cgi_dir => $cgi_dir );

my $cgi_path = $build->prompt("What is the relative url of the cgi-bin on your webserver?");
$build->notes( cgi_path => $cgi_path );

my $js_dir = $build->prompt("What is the location of your javascript Directory?");
$build->notes( js_dir => $js_dir );

$build->create_build_script();



