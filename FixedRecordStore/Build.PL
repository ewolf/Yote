use strict;
use warnings;
use Module::Build;


my $builder = Module::Build->new(
    add_to_cleanup      => [ 'DB-DataStore-*' ],
    build_requires => {
        'Test::More'            => 0,
        'Module::Build'         => 0,
    },
    dist_abstract      => 'Simple and fast record based data store',
    create_makefile_pl => 'traditional',
    license            => 'perl',
    module_name        => 'DB::DataStore',
    release_status     => 'stable',
    test_files         => [ 't/datastore.t', ],
    requires => {
        'perl'                  => 'v5.9.4',
    },
    );

$builder->create_build_script();
