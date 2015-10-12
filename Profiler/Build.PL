use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    add_to_cleanup      => [ 'Devel-*' ],
    build_requires => {
        'Test::More' => 0,
        'Module::Build' => 0.40,
    },
    create_makefile_pl => 'traditional',
    license            => 'perl',
    module_name        => 'Devel::SimpleProfiler',
    release_status     => 'stable',
    test_files         => [ 't/yotedb.t', ],
    requires => {
        'perl'          => 'v5.12',
        'Aspect'        => '1.04',
    },
    );

$builder->create_build_script();
