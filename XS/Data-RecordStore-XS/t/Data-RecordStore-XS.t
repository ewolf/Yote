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

diag( "Open Silo" );
test_open_silo();

diag( "Put Record" );
test_put_record();

diag( "Broken File" );
test_broken_file();

diag( "Transactions" );
test_trans();


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


sub test_open_silo {
    my $dir = tempdir( CLEANUP => 1 );

#    local $Data::RecordStore::Silo::MAX_SIZE = 80;
    my $silo;

    my $silo_dir = "$dir/silo";

    eval { $silo = Data::RecordStore::Silo::XS->open_silo( 'A*', $silo_dir ); };

    like( $@, qr/annot open a zero/, 'tried to open zero store' );
    undef $@;
    ok( !( -e "$silo_dir/0" ), 'nothing created silo file created' );

    {
        local( $SIG{ __WARN__ } ) = $SIG{ __DIE__ };

        eval {$silo = Data::RecordStore::Silo::XS->open_silo( 'A*', $silo_dir, 199 ); };
        like( $@, qr/above the set max size/, 'got warning for opening a silo with a single record larger than the max size' );
        undef $@;
        ok( !( -e "$silo_dir/0" ), 'still nothing created silo file created' );
    }

    my $toobigdir = "$dir/toobig";
    eval {$silo = Data::RecordStore::Silo::XS->open_silo( 'A*', "$toobigdir", 199 ); };
    ok( ! $@, "no die for opening a store with a record larger than the max silo size (just a warning)" );
    ok( -e "$toobigdir/0", 'initial silo file created for toobig' );
    is( $silo->[1], 199, "199 record size" );
    is( $silo->[2], 199, "199 file size" );
    is( $silo->[3], 1,  "1 max records per silo file" );


    my $cantdir = "$dir/cant";

    open my $out, ">", $cantdir;
    print $out "TOUCH\n";
    close $out;
    eval {$silo = Data::RecordStore::Silo::XS->open_silo( 'A*', "$cantdir", 30 ); };
    like( $@, qr/not a directory/, 'dies if directory is not a directory' );
    undef $@;

    unlink $cantdir;
    mkdir $cantdir, 0444;

    if( ! -w $cantdir ) {
        # this test is useless if performed by root which would always be allowed
        # to write
        eval {$silo = Data::RecordStore::Silo::XS->open_silo( 'A*', "$cantdir", 30 ); };
        like( $@, qr/Unable to open/, 'directory exists not writeable' );
        undef $@
    }

    $silo = Data::RecordStore::Silo::XS->open_silo( 'A*', $silo_dir, 20 );
    is( $silo->[1], 20, "20 record size" );
    is( $silo->[2], 80, "80 file size" );
    is( $silo->[3], 4,  "4 max records per silo file" );

    $silo = Data::RecordStore::Silo::XS->open_silo( 'AAA', $silo_dir );
    is( $silo->[1], 3, "record size 3" );

    eval {$silo = Data::RecordStore::Silo::XS->open_silo( 'AAA', $silo_dir, 30 ); };
    like( $@, qr/record size does not agree/, 'template and size given dont agree' );
    undef $@;

    $silo = Data::RecordStore::Silo::XS->open_silo( 'A*', $silo_dir, 30 );
    is( $silo->[1], 30, "30 record size" );
    is( $silo->[2], 60, "60 file size" );
    is( $silo->[3], 2,  "2 max records per silo file" );

    $silo = Data::RecordStore::Silo::XS->open_silo( 'A*', $silo_dir, 41 );
    is( $silo->[1], 41, "41 record size" );
    is( $silo->[2], 41, "41 file size" );
    is( $silo->[3], 1,  "1 max records per silo file" );

    $silo = Data::RecordStore::Silo::XS->open_silo( 'A*', $silo_dir, 20 );
#    $silo->_ensure_entry_count( 9 );

    # my( @files ) = $silo->_files;

    # is( $silo->[0], "$dir/silo", "directory" );
    # is_deeply( \@files, [ 0, 1, 2 ], 'three silo files' );
    # is( $silo->entry_count, 9, "9 entries" );
    # is( -s "$dir/silo/0", 80, "first file 80 bytes" );
    # is( -s "$dir/silo/1", 80, "second file 80 bytes" );
    # is( -s "$dir/silo/2", 20, "last file 20 bytes" );

    $silo->empty;
    ok( -e "$dir/silo/0", "first file still exists" );
    is( -s "$dir/silo/0", 0, "first file zero bytes after empty" );
    ok( ! (-e "$dir/silo/1"), "second file gone" );
    ok( ! (-e "$dir/silo/2"), "third file gone" );

    $silo->unlink_store;
    ok( ! (-e "$dir/silo"), "unlinked completely" );

} #test_open_silo

sub test_put_record {
    # actually open a silo

    my $dir = tempdir( CLEANUP => 1 );
    my $silo_dir = "$dir/silo";

    local $Data::RecordStore::Silo::MAX_SIZE = 80;

    my $silo = Data::RecordStore::Silo::XS->open_silo( 'A*', $silo_dir, 20 );

    # make sure 0 file was created
    ok( -e "$silo_dir/0", 'initial silo file created' );

    eval { $silo->put_record( 0, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id too low' );
    undef $@;

    eval { $silo->put_record( -1, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id way too low' );
    undef $@;

    eval { $silo->put_record( 2, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id too high' );

    is( $silo->entry_count, 0, "no entries yet" );

    eval { $silo->put_record( 1, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id too high' );

    is( $silo->entry_count, 0, "still no entries yet" );

    my $id = $silo->next_id;
    is( $silo->entry_count, 1, "first entry" );
    is( $id, 1, "first entry id" );

    # what happens if you try to write a record that is too big
    eval { $silo->put_record( 1, "x" x 22 ); };
    like( $@, qr/record too large/, 'record too large' );

    eval { $silo->put_record( 2, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id too high' );

    is_deeply( $silo->get_record( 1 ), [''], "no data in first entry yet" );

    eval { $silo->get_record( 2 ); };
    like( $@, qr/out of bounds/, 'id too high' );


    eval { $silo->get_record( 0 ); };
    like( $@, qr/out of bounds/, 'id too low' );

    # test how many silo files are generated
#    my( @files ) = $silo->_files;
#    is_deeply( \@files, [ 0 ], 'one silo file' );

#    is( $silo->[3], 4, 'four max records per silo file' );
#    is( $silo->[2], 80, '80 sized silo file' );

    $silo->empty;

    local $Data::RecordStore::Silo::MAX_SIZE = 27; #3 records

    $silo = Data::RecordStore::Silo::XS->open_silo( 'IAI', $silo_dir );
    is( $silo->[1], 9, "record size 9 bytes");
    $id = $silo->next_id;
    is( $id, 1, "first id" );
    is( $silo->entry_count, 1, "ec 1" );
    $silo->put_record( 1, [ 43, "Q", 22 ] );
    is( -s "$silo_dir/0", 9, "file size now 9 bytes" );
    my $data = $silo->get_record( 1 );
    is_deeply( $data, [  43, "Q", 22 ], 'correct data stored for first record' );
    is( $silo->entry_count, 1, "ec still 1" );

    my $pop_data = $silo->pop;
    is_deeply( $pop_data, $data, 'popped data is the first record' );
    is( $silo->entry_count, 0, "ec back to 0" );
    $id = $silo->next_id;
    is( $id, 1, "back to first id" );
    $silo->pop;
    is( $silo->entry_count, 0, "ec back to 0" );

    my $next_id = $silo->push( [ 1, "A", 1001 ] );
    is( $next_id, 1, "pushed id" );
    $next_id = $silo->push( [ 2, "b", 1001 ] );
    is( $next_id, 2, "pushed id" );
    $next_id = $silo->push( [ 3, "c", 1001 ] );
    is( $next_id, 3, "pushed id" );
    $next_id = $silo->push( [ 4, "D", 1001 ] );
    is( $next_id, 4, "pushed id" );

    is( $silo->entry_count, 4, "now at 4 things" );
    is( -s "$silo_dir/0", 27, "first file now 27" );
    is( -s "$silo_dir/1", 9, "second file now 9" );

    is_deeply( $silo->last_entry, [ 4, "D", 1001 ], "LAST ENTRY AGREES" );
    is( $silo->entry_count, 4, "now at 4 things" );
    is( -s "$silo_dir/0", 27, "first file now 27" );
    is( -s "$silo_dir/1", 9, "second file now 9" );

    $data = $silo->pop;
    is_deeply( $silo->last_entry, [ 3, "c", 1001 ], "LAST ENTRY AGREES" );
    ok( !(-e "$silo_dir/1"), "second file removed" );
    is_deeply( $data, [ 4, "D", 1001 ], "pop 4" );

    $data = $silo->pop;
    is_deeply( $silo->last_entry, [ 2, "b", 1001 ], "LAST ENTRY AGREES" );
    is( -s "$silo_dir/0", 18, "first file smaller" );
    is_deeply( $data, [ 3, "c", 1001 ], "pop 3" );

    $data = $silo->pop;
    is_deeply( $silo->last_entry, [ 1, "A", 1001 ], "LAST ENTRY AGREES" );
    is( -s "$silo_dir/0", 9, "first file smaller" );
    is_deeply( $data, [ 2, "b", 1001 ], "pop 2" );

    $data = $silo->pop;
    is( $silo->last_entry, undef, "No last entry" );
    is( $silo->entry_count, 0, "no entries after pop" );
    is( -s "$silo_dir/0", 0, "first file emptied" );
    ok( ! (-e "$silo_dir/1"), "no second file" );
    ok( ! (-e "$silo_dir/2"), "no third file" );
    is_deeply( $data, [ 1, "A", 1001 ], "pop 1" );

    # 3 records, 2 files
    $silo->push( [ 1, "A", 1001 ] ); #0
    is( $silo->entry_count, 1, "push 1" );
    $silo->push( [ 22, "b", 10003 ] ); #1
    is( $silo->entry_count, 2, "push 2" );
    $silo->push( [ 333, "C", 10003 ] ); #2
    is( $silo->entry_count, 3, "push 3" );
    $silo->push( [ 4444, "d", 10003 ] ); #3
    is( $silo->entry_count, 4, "push 4" );
    $silo->push( [ 55555, "C", 10003 ] ); #4
    is( $silo->entry_count, 5, "push 5" );

    eval { $silo->_copy_record( 0, -1 ); };
    like( $@, qr/to_index -1 out of bounds/, 'to id too low' );
    undef $@;

    eval { $silo->_copy_record( 0, 5 ); };
    like( $@, qr/to_index 5 out of bounds/, 'to id too high' );
    undef $@;

    eval { $silo->_copy_record( -1, 0 ); };
    like( $@, qr/from_index -1 out of bounds/, 'from id too low' );
    undef $@;

    eval { $silo->_copy_record( 5, 0 ); };
    like( $@, qr/from_index 5 out of bounds/, 'from id too high' );
    undef $@;


    $silo->_copy_record( 3, 2 ); # idx used, not id like below
    is_deeply( $silo->get_record( 4 ), [ 4444, "d", 10003 ], "record after copy" );
    is_deeply( $silo->get_record( 3 ), [ 4444, "d", 10003 ], "copied record" );

} #test_put_record

sub test_broken_file {

    my $dir = tempdir( CLEANUP => 1 );
    my $silo_dir = "$dir/silo";

    local $Data::RecordStore::Silo::MAX_SIZE = 80;

    my $silo = Data::RecordStore::Silo::XS->open_silo( 'A*', $silo_dir, 20 );

    # make sure 0 file was created
    ok( -e "$silo_dir/0", 'initial silo file created' );

    $silo->_ensure_entry_count( 4 );
    is( $silo->entry_count, 4, "store has four entries" );
    my $next_id = $silo->next_id;
    is( $next_id, 5, "next id is 5" );
    is( $silo->entry_count, 5, "store has 5 entries" );

    my( @files ) = $silo->_files;
    is_deeply( \@files, [ 0, 1 ], 'two silo files' );

    # break the last file here
    truncate "$silo->[0]/1", 19; #remove the last byte from this record 'breaking' it
    is( $silo->entry_count, 4, "entry count back down to 4" );
    eval { $silo->get_record( 5 ) };
    like( $@, qr/out of bounds/, "garbled record not getable" );
    undef $@;
    $next_id = $silo->next_id;
    is( $next_id, 5, "next id is again 5" );
    is( $silo->entry_count, 5, "store back up to 5 entries" );


    # remove the last file and mess with the first one.
    unlink "$silo->[0]/1";
    truncate "$silo->[0]/0", 71;

    eval { $silo->get_record( 5 ) };
    like( $@, qr/out of bounds/, "truncated not getable" );
    undef $@;

    eval { $silo->get_record( 4 ) };
    like( $@, qr/out of bounds/, "partially truncated not getable" );
    undef $@;

    is( $silo->entry_count, 3, "entry count back down to 3" );
    $next_id = $silo->next_id;
    is( $next_id, 4, "next id is again 4" );



} #test_broken_file


sub check {
    my( $store, $txt, %checks ) = @_;

    my $silo = $store->_get_silo(4);

    my( @trans ) = $store->list_transactions;
    is( @trans, $checks{trans}, "$txt : transactions" );
    is( $store->entry_count, $checks{entries}, "$txt: active entries" );
    is( $store->[1]->entry_count, $checks{ids}, "$txt: ids in index" );
    is( $store->[2]->entry_count, $checks{recyc}, "$txt: recycle count" );
    is( $silo->entry_count, $checks{silo}, "$txt: silo count" );

} #check

sub test_trans {
    my $dir = tempdir( CLEANUP => 1 );

    my $store = Data::RecordStore->open_store( $dir );
    check( $store, "init",
           entries => 0,
           trans   => 0,
           ids     => 0,
           recyc   => 0,
           silo    => 0,
        );

    my $trans = $store->create_transaction;
    check( $store, "create trans",
           entries => 0,
           ids     => 0,
           silo    => 0,
           recyc   => 0,
           trans   => 1, #trans created
        );

    $trans->commit;
    check( $store, "commit trans",
           entries => 0,
           ids     => 0,
           silo    => 0,
           recyc   => 0,
           trans   => 0, #trans completed
        );

    eval { $trans->stow("WOOBUU"); };
    like( $@, qr/not active/, "cant stow on inactve" );
    undef $@;

    eval { $trans->delete_record(3); };
    like( $@, qr/not active/, "cant delete record on inactve" );
    undef $@;

    eval { $trans->recycle_id(3); };
    like( $@, qr/not active/, "cant recycle record on inactve" );
    undef $@;

    check( $store, "still nada",
           trans   => 0,
           entries => 0,
           recyc   => 0,
           ids     => 0,
           silo    => 0,
        );

    $trans = $store->create_transaction;
    check( $store, "new trans",
           trans   => 1, #new trans
           entries => 0,
           ids     => 0,
           silo    => 0,
           recyc   => 0,
        );


    my $id = $trans->stow( "HERE IS SOME" );

    check( $store, "trans stow 1",
           trans   => 1,
           entries => 1, # one id in use
           ids     => 1, # one id created
           silo    => 1, # one written to silo
           recyc   => 0,
        );

    $trans->stow( "HERE IS MORE", $id );

    check( $store, "trans stow 2",
           trans   => 1,
           entries => 1,
           recyc   => 0,
           ids     => 1,
           silo    => 2, # same id written to silo
        );

    $trans->recycle_id( $id );

    check( $store, "trans recycle",
           trans   => 1,
           entries => 1,
           recyc   => 0,
           ids     => 1,
           silo    => 2,
        );

    my $next_id = $store->next_id;

    is( $next_id, 2, "second id created during trans recycle" );

    check( $store, "store next id",
           trans   => 1,
           entries => 2, # 2 ids in use
           recyc   => 0,
           ids     => 2, # 2 ids created
           silo    => 2,
        );

    $trans->commit;

    check( $store, "trans stow 1 after commit",
           trans   => 0, # transaction committed
           entries => 1, # one recycled out, other is next id
           recyc   => 1, # recycle
           ids     => 2,
           silo    => 0, # 2 instances of one id recycled away
       );

    $next_id = $store->next_id;

    is( $next_id, 1, "next id is recycled 1 after commit" );

    check( $store, "after trans recyc next id",
           trans   => 0,
           entries => 2, # 1 and 2
           recyc   => 0, # recycle done
           ids     => 2,
           silo    => 0,
        );


    $trans = $store->create_transaction;

    check( $store, "new transaction",
           trans   => 1, #new trans
           entries => 2,
           recyc   => 0,
           ids     => 2,
           silo    => 0,
        );

    $id = $next_id;
    $trans->stow( "HERE IS SOME", $id );

    check( $store, "transaction stow",
           trans   => 1,
           entries => 2,
           recyc   => 0,
           ids     => 2,
           silo    => 1, #trans stow
        );

    $trans->stow( "HERE IS MORE", $id );

    check( $store, "addl stow",
           trans   => 1,
           entries => 2,
           recyc   => 0,
           ids     => 2,
           silo    => 2, #addl stow on same id
        );

    $trans->recycle_id( $id );

    check( $store, "trans recyc",
           trans   => 1,
           entries => 2,
           recyc   => 0, #recycle not yet happened
           ids     => 2,
           silo    => 2,
        );

    $next_id = $store->next_id;

    is( $next_id, 3, "next id is three" );

    check( $store, "after next id",
           trans   => 1,
           entries => 3, #after next id
           recyc   => 0,
           ids     => 3, #after next id
           silo    => 2,
        );

    $trans->rollback;

    # also, test to make sure a broken written record at the end of a silo file
    #     doesn't sink the whole thing

    # there is something in the silo that shouldnt be there
    #     rollback didnt work for this case

    check( $store, "after transaction rollback",
           trans   => 0, #transaction done
           entries => 3,
           recyc   => 0,
           ids     => 3,
           silo    => 0,
        );

    $next_id = $store->next_id;
    is( $next_id, 4, "next id is 4 after aborted recycle" );

    check( $store, "after aborted recycle",
           trans   => 0,
           entries => 4,
           recyc   => 0,
           ids     => 4,
           silo    => 0,
        );



    $trans = $store->create_transaction;
    check( $store, "new trans",
           trans   => 1, #new trans
           entries => 4,
           recyc   => 0,
           ids     => 4,
           silo    => 0,
        );

    $id = $trans->stow( "HERE IS SOME" );
    is( $id, 5, "new trans new id" );

    check( $store, "new trans will store",
           trans   => 1, #new trans
           entries => 5, #new id
           recyc   => 0,
           ids     => 5, #new id generated
           silo    => 1, #something in silo
        );

    $id = $trans->stow( "CHANGED mind", $id );
    is( $id, 5, "new trans new id still 5" );

    check( $store, "new trans will store overwrite",
           trans   => 1,
           entries => 5,
           recyc   => 0,
           ids     => 5, #same id used
           silo    => 2, #one more silo entry though
       );

    $id = $trans->stow( "MEW NEW mind" );
    is( $id, 6, "new trans new id now 6" );

    check( $store, "new trans will store overwrite",
           trans   => 1,
           entries => 6, #new entry
           recyc   => 0,
           ids     => 6, #new id for new entry
           silo    => 3, #one more silo entry though
       );

    $trans->commit;

    is( $store->fetch( $id ), "MEW NEW mind", "transaction value" );

    check( $store, "new trans commit",
           trans   => 0,
           entries => 6,
           recyc   => 0,
           ids     => 6, #same id used
           silo    => 2, #one more silo entry though
       );

    my $dir2 = tempdir( CLEANUP => 1 );
    my $store2 = Data::RecordStore->open_store( $dir2 );
    my $val1 = "x" x 12;
    my $val2 = "x" x 1224;
    my( @ids );
    for (1..10) {
        push @ids, $store2->stow( $val1 );
    }
    my $t = $store2->create_transaction;
    for my $id (@ids) {
        $t->stow( $val2, $id );
    }
    check( $store2, "simple swap check before commit",
           trans   => 1,  #1 transaction
           entries => 10, #new entry
           recyc   => 0,
           ids     => 10, #new id for new entry
           silo    => 10, #all in silo 4
       );
    eval {
        $t->commit;
    };
    unlike( $@, qr/\S/, 'no commit error simple' );
    unlike( $@, qr/_swapout/, 'no swapout error simple' );
    check( $store2, "simple swap check after commit",
           trans   => 0,
           entries => 10, #new entry
           recyc   => 0,
           ids     => 10, #new id for new entry
           silo    => 0, # none in silo 4 aymore
       );

    my $dir3 = tempdir( CLEANUP => 1 );
    my $store3 = Data::RecordStore->open_store( $dir3 );
    $val1 = "x" x 12;
    $val2 = "x" x 1224;
    my $val3 = "x" x 12;
    my $val4 = "x" x 10_000;
    ( @ids ) = ();
    for (1..10) {
        push @ids, $store3->stow( $val1 );
    }
    $t = $store3->create_transaction;
    for my $id (@ids) {
        $t->stow( $val2, $id );
    }
    for my $id (@ids) {
        $t->stow( $val3, $id );
    }
    
    for my $id (@ids) {
        $t->stow( $val4, $id );
    }
    check( $store3, "multimove swap check before commit",
           trans   => 1,  #1 transaction
           entries => 10, #new entry
           recyc   => 0,
           ids     => 10, #new id for new entry
           silo    => 20, #all twice in silo 4
       );
    eval {
        $t->commit;
    };
    unlike( $@, qr/\S/, 'no commit error multimove' );
    unlike( $@, qr/_swapout/, 'no swapout error multimove' );
    check( $store3, "multimove swap check after commit",
           trans   => 0,
           entries => 10, #new entry
           recyc   => 0,
           ids     => 10, #new id for new entry
           silo    => 0, #no more in silo 4
       );

    my $dir4 = tempdir( CLEANUP => 1 );
    my $store4 = Data::RecordStore->open_store( $dir );
    $val1 = "x" x 12;
    $val2 = "x" x 1224;
    $val3 = "x" x 12;
    $val4 = "x" x 10_000;
    for (1..10) {
        push @ids, $store4->stow( $val1 );
    }

    $t = $store4->create_transaction;
    for my $id (@ids) {
        $t->stow( $val2, $id );
    }
    eval {
        $t->commit;
    };
    unlike( $@, qr/\S/, 'no commit error moar multimove' );
    unlike( $@, qr/_swapout/, 'no swapout error moar multimove' );

    $t = $store4->create_transaction;
    for my $id (@ids) {
        $t->stow( $val3, $id );
    }
    for my $id (@ids) {
        $t->stow( $val4, $id );
    }
    eval {
        $t->commit;
    };
    unlike( $@, qr/\S/, 'no commit error moar multimove' );
    unlike( $@, qr/_swapout/, 'no swapout error moar multimove' );


} #test_trans


__END__
