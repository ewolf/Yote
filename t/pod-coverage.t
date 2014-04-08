use Test::More;
use strict;
use warnings;
eval "use Test::Pod::Coverage 1.00";
plan skip_all => "Test::Pod::Coverage 1.00 required for testing POD coverage" if $@;
my $parms = { trustme => [qr/LOCK_NEVER/] };

#
# Some of the modules are optional and may not compile. Exclude those from the pod check.
# The other checks will uncover malfunctioning modules.
#
my( @mods ) = grep { /^Yote/ } grep { eval("use $_"); !$@ } all_modules( "lib" );

for my $mod ( @mods ) {
    pod_coverage_ok( $mod, $parms );
}
done_testing();
exit( 0 );
