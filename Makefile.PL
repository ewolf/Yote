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
	'Acme::Damn'            => 0,
	'forks'                 => 0,
	'File::Copy'             => 0,
	'File::Path'             => 0,
	'File::chmod'            => 0,
	'DBI'                   => 0,
    },
);

my %dirs = (
    cgi_dir   => "What is the location of your cgi-bin directory?",
    js_dir    => "What is the location of your javascript Directory?",
    html_root => "What is the location of your web root Directory?",
    cgi_path  => "What is the relative url of the cgi-bin on your webserver?",
    js_path  => "What is the relative url of the javascript on your webserver?",
    );
for my $key (sort keys %dirs) {
    my $dir;
    until( -d $dir ) {
	$dir = $build->prompt( $dirs{$key} );
	last if $key =~ /_path$/; #not a dir on the file system but a path on the webserver
	unless( -d $dir ) {
	    print "Directory '$dir' not found. Try again\n";
	}
    }
    $build->notes( $key => $dir );
}

$build->create_build_script();



