use strict;
use warnings;
use Module::Build;


my $builder = Module::Build->new(
    add_to_cleanup      => [ 'Lock-Server-*' ],
    build_requires => {
        'Test::More'            => 0,
        'Module::Build'         => 0,
    },
    dist_abstract      => 'Light-weight socket based resource locking manager.',
    create_makefile_pl => 'traditional',
    license            => 'perl',
    module_name        => 'Lock::Server',
    release_status     => 'stable',
    dist_version       => 1.64,
    version            => 1.64,
    test_files         => [ 't/locktest.t', ],
    requires => {
        'perl'                  => 'v5.9.4',
    },
 );

$builder->create_build_script();
