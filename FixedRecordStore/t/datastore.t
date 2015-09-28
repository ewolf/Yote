use strict;
use warnings;

use DB::DataStore;

use Data::Dumper;
use File::Temp qw/ :mktemp tempdir /;
use Test::More;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    use_ok( "DB::DataStore" ) || BAIL_OUT( "Unable to load DB::DataStore" );
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

my $dir = tempdir( CLEANUP => 1 );
test_suite();
done_testing;

exit( 0 );


sub test_suite {

    my $store = DB::DataStore->open( $dir );
    my $id  = $store->stow( "FOO FOO" );
    my $id2 = $store->stow( "BAR BAR" );
    
    is( $id2, $id + 1, "Incremental object ids" );
    is( $store->fetch( $id ), "FOO FOO", "first item saved" );
    is( $store->fetch( $id2 ), "BAR BAR", "second item saved" );

    $store->recycle( 1 );
    my $id3 = $store->stow( "BUZ BUZ" );
    is( $id3, $id, "Got back recycled id" );
    my $id4 = $store->stow( "LA LA" );
    is( $id4, $id2 + 1, "Post recycled id" );

} #test suite


__END__
