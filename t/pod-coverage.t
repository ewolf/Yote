use Test::More;
use strict;
use warnings;
eval "use Test::Pod::Coverage 1.00";
plan skip_all => "Test::Pod::Coverage 1.00 required for testing POD coverage" if $@;
my $parms = { trustme => [qr/LOCK_NEVER/] };
all_pod_coverage_ok( $parms );
exit( 0 );
