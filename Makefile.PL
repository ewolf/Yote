use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'Yote',
    VERSION_FROM => 'lib/Yote.pm', # finds \$VERSION
    AUTHOR       => 'Eric Wolf (coyocanid@gmail.com)',
    ABSTRACT     => 'Web App Server w/ autopersistant objects',
    PREREQ_PM    => {
		     'Config::Simple'        => 4.58,
	             'App::Options'          => 1.12,
		     'DBD::Mysql'            => 4.014,
		     'DBD::SQLite'           => 1.35,
		     'HTTP::Request::Params' => 1.01,
		     'JSON'                  => 2.22,
		     'MIME::Base64'          => 3.08,
		     'Net::Server::Fork'     => 0.99,
		     'IO::Socket'            => 1.31,
                     'Test::Simple'          => 0.44,
		     'WeakRef'               => 0.01,
                    },
    EXE_FILES    => ['script/yote_server'],
);
