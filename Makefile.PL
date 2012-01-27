use Module::Build;

use YoteModule;

use File::Spec::Functions qw( catfile catdir rel2abs );
my $package_base = catdir(File::Spec->rootdir, qw( usr local yote ));

my @args;
do { $_ =~ /^package_base=(.+)$/ ? $package_base = $1 : push @args, $_ } for (@ARGV);


my $build = YoteModule->new( 
    dist_author   => 'Eric Wolf (coyocanid@gmail.com)',
    install_types => [qw( lib script db )],
    package_base  => $package_base,
    script_files  => [ 'script/yote_server' ],
    dist_abstract => 'Web App Server w/ autopersistant objects',
    dist_version_from => 'lib/Yote/WebAppServer.pm',
    module_name   => 'Yote',
    license       => 'perl',
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
    },
    )->create_build_script();

