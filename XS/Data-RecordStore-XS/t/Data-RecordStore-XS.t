# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl Data-RecordStore-XS.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use File::Temp qw/ :mktemp tempdir /;
use Test::More;
BEGIN { use_ok('Data::RecordStore::XS') };

diag( "HELLO" );

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.
my $diry = tempdir( CLEANUP => 1 );

my $store = Data::RecordStore::XS->open_store( $diry );
is( $store->next_id, 1, "First ID" );
is( $store->next_id, 2, "2nd ID" );

my $id = $store->stow( "FOOBY" );
is( $id, 3, "3rd ID from stow" );
is( $store->fetch( 3 ), "FOOBY", "first fetch" );

my $silo_dir = tempdir( CLEANUP => 1 );
my $silo = Data::RecordStore::Silo::XS->open_silo( "II", $silo_dir );
is( $silo->next_id, 1, "first silo id" );
is( $silo->next_id, 2, "2nd silo id" );
$id = $silo->push( [ 1, 2 ] );
is( $id, 3, "3rd id from push" );
$silo->put_record( 2, [ 24, 9 ] );

my $r1 = $silo->get_record( 3 );
is_deeply( $r1, [ 1, 2 ], "first stored record" );
is_deeply( $silo->get_record(2), [ 24, 9 ], "second stored record" );


# -----------------------------------------------------
#               init
# -----------------------------------------------------

my $dir = tempdir( CLEANUP => 1 );
my $dir2 = tempdir( CLEANUP => 1 );
my $dir3 = tempdir( CLEANUP => 1 );

diag "Test Suite";
test_suite();

diag "Record Silos";
test_record_silos();

diag "Done";
done_testing;

exit( 0 );


sub test_suite {

    my $store = Data::RecordStore::XS->open_store( $dir );

    ok( ! $store->has_id( 1 ), "no first id yet" );
    ok( ! $store->has_id( 2 ), "no second id yet" );

    my $id  = $store->stow( "FOO FOO" );
    ok( $store->has_id( 1 ), "now has first id" );
    ok( ! $store->has_id( 2 ), "still no second id yet" );
    my $id2 = $store->stow( "BAR BAR" );
    ok( $store->has_id( 2 ), "now has second id" );
    my $id3 = $store->stow( "Käse essen" );
    $store = Data::RecordStore::XS->open_store( $dir );
    is( $id2, $id + 1, "Incremental object ids" );
    is( $store->fetch( $id ), "FOO FOO", "first item saved" );
    is( $store->fetch( $id2 ), "BAR BAR", "second item saved" );
    is( $store->fetch( $id3 ), "Käse essen", "third item saved" );

    my $ds = Data::RecordStore::Silo::XS->open_silo( "LLA4", "$dir2/filename" );
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

    my $cur_silo = $store->_get_silo( 8 );
    is( $cur_silo->entry_count, 0, "silo #8 empty" );

    #
    # Try testing the moving of a record
    #
    $store = Data::RecordStore::XS->open_store( $dir3 );
    $cur_silo = $store->_get_silo( 8 );

    $id = $store->stow( "x" x 2968 ); # 7 is 1085, 8 is 2969, should be in 8

    is( $store->entry_count, 1, "one entry count in store" );

    # 3, 4,  5,  6,   7,   8,    9,
    # 9,43,137,392,1085,2969, 8092,  (1 + e^n - 12)
    is( $cur_silo->entry_count, 1, "One entry in silo #8" );

    my $yid = $store->stow( "y" x 2961 ); # 7 is 1085, 8 is 2969, should be in 8
    is( $yid, 2, "Second ID" );
    is( $cur_silo->entry_count, 2, "Two entry in silo #8" );

    $store->stow( "x" x 3000, $id );  # 8 is max 2969, should be in 9

    is( $cur_silo->entry_count, 1, "Entry relocated from silo #8" );
    my $new_silo = $store->_get_silo( 9 );
    is( $new_silo->entry_count, 1, "One entry relocated to silo #9" );
    is( $store->fetch( $yid ), "y" x 2961, "correctly relocated data" );
    # try for a much smaller relocation

    $new_silo = $store->_get_silo( 5 );
    is( $new_silo->entry_count, 0, "No entries in silo #5" );
    $store->stow( "x" x 90, $id );

    $new_silo = $store->_get_silo( 9 );
    is( $new_silo->entry_count, 0, "One entry relocated from silo #9" );
    $new_silo = $store->_get_silo( 5 );
    is( $new_silo->entry_count, 1, "One entry relocated to silo #5" );
    # test for record too large. idx out of bounds

    my $xid = $store->stow( "x" x 90 );
    is( $new_silo->entry_count, 2, "Two entries now in silo #5" );
    $store->delete_record( $id );
    is( $new_silo->entry_count, 1, "one entries now in silo #5 after delete" );
    # test store empty
    $store->empty;
    ok( !$store->has_id(1), "does not have any entries" );
    ok( !$store->has_id(0), "does not have any entries" );

    is( $store->entry_count, 0, "empty then no entries" );

    $store->stow( "BOOGAH", 4 );
    is( $store->next_id, '5', "next id is 5" );
    is( $store->entry_count, 5, "5 entries after skipping ids plus asking to generate the next one" );
    ok( $store->has_id(4), "has entry four" );
    ok( ! $store->has_id(1), "no entry one, was skipped" );

    $store->recycle_id( 3 );
    is( $store->entry_count, 4, "4 entries after recycling entry" );
    is( $store->next_id, 3, 'recycled id' );
    is( $store->entry_count, 5, "5 entries after recycling empty id" );
    is( $store->next_id, 6, 'no more recycling ids' );
    is( $store->fetch( 4 ), "BOOGAH" );
    $store->recycle_id( 4 );
    ok( ! $store->fetch( 4 ), "4 was recycled" );
    is( $store->next_id, 4, 'recycled id 4' );

    $store->stow( "TEN", 10 );
    is( $store->entry_count, 10, "entry count explicitly set" );
    is( $store->next_id, 11, 'after entry count being set' );

    $store->recycle_id(2);
    is( $store->next_id, 2, 'recycled id' );
    $store->recycle_id(3);
    $store->recycle_id(4);
    $store->empty_recycler;

    is( $store->next_id, 12, 'after recycler emptied' );

} #test suite

sub test_record_silos {

#    $Data::RecordStore::XS::Silo::MAX_SIZE = 80;

    my $store = Data::RecordStore::XS->open_store( $dir );
    $store->empty;

    is( $store->entry_count, 0, "Emptied store" );

    for( 1..11 ) {
        my $id = $store->next_id;
        $store->stow( "GZAA $id", $id );
        is( $id, $_, "got correct id $_" );
    }

} #test_record_silos

__END__
