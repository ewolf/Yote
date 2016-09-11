use strict;
use warnings;

use Data::RecordStore;

use Data::Dumper;
use File::Temp qw/ :mktemp tempdir /;
use Test::More;
use JSON;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    use_ok( "Data::RecordStore" ) || BAIL_OUT( "Unable to load Data::RecordStore" );
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

my $dir = tempdir( CLEANUP => 1 );
my $dir2 = tempdir( CLEANUP => 1 );
test_suite();
done_testing;

exit( 0 );


sub test_suite {

    my $store = Data::RecordStore->open( $dir );
    my $id  = $store->stow( "FOO FOO" );
    my $id2 = $store->stow( "BAR BAR" );
    my $json_data = encode_json( {
        todo => [ "Käse essen"  ],
                             } );
    my $id3 = $store->stow( $json_data );

    $store = Data::RecordStore->open( $dir );    
    is( $id2, $id + 1, "Incremental object ids" );
    is( $store->fetch( $id ), "FOO FOO", "first item saved" );
    is( $store->fetch( $id2 ), "BAR BAR", "second item saved" );
    is( $store->fetch( $id3 ), encode_json( {
        todo => [ "Käse essen"  ],
                                        } ), "third item saved" );
    
    $store->recycle( $id );
    my $id4 = $store->stow( "BUZ BUZ" );
    is( $id4, $id, "Got back recycled id" );
    my $id5 = $store->stow( "LA LA" );
    is( $id5, $id3 + 1, "Post recycled id" );

    my $ds = Data::RecordStore::FixedStore->open( "LLA4", "$dir2/filename" );
    my( @r ) = (
        [],
        [ 12,44,"BOO" ],
        [ 2342,300,"QSA" ],
        [ 66,89,"DDI" ],
        [ 2,139,"FUR" ],
        [ 12,19939,"LEG" ],
        );

    $ds->push( $r[1] );
    $ds->push( $r[2] );
    $ds->push( $r[3] );
    
    is_deeply( $ds->get_record( 2 ), $r[2], "Second record" );
    is_deeply( $ds->get_record( 1 ), $r[1], "First record" );
    is_deeply( $ds->get_record( 3 ), $r[3], "Third record" );

# splice and get_records is deprecated for now until needed
#    is_deeply( $ds->get_records( 2, 2 ), [ $r[2], $r[3] ], "get_records multiple" );
#    is_deeply( $ds->get_records( 1, 1 ), [ $r[1] ], "get_records first" );
#    is_deeply( $ds->get_records( 3, 1 ), [ $r[3] ], "get_records last" );
#
#    $ds->splice_records( 2, 1, $r[4], $r[5] );
#    is( $ds->entry_count, 4, "four records after splice" );
#    is_deeply( $ds->get_records( 1, 4 ), [ $r[1], $r[4], $r[5], $r[3] ], "correct records after splice" );

    # test for record too large. idx out of bounds
    

} #test suite


__END__
