use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    add_to_cleanup      => [ 'Yote-*' ],
    build_requires => {
        'Test::More' => 0,
        'Module::Build' => 0.40,
    },
    dist_abstract      => 'oject store',
    create_makefile_pl => 'traditional',
    license            => 'perl',
    module_name        => 'Yote',
    release_status     => 'stable',
    test_files         => [ 't/yotedb.t', ],
    requires => {
        'perl'                  => 'v5.10',
        'Data::RecordStore'     => 3.15,
    },
    );

$builder->create_build_script();
