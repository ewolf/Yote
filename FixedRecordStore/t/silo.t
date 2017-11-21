use strict;
use warnings;

use Data::RecordStore;

use Data::Dumper;
use File::Temp qw/ :mktemp tempdir /;
use Test::More;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    use_ok( "Data::RecordStore" ) || BAIL_OUT( "Unable to load Data::RecordStore" );
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

test_suite();

done_testing;

exit( 0 );


sub test_suite {
    test_open_silo();
    test_put_record();
    test_broken_file();
} #test_suite

sub test_open_silo {
    my $dir = tempdir( CLEANUP => 1 );

    local $Data::RecordStore::Silo::MAX_SIZE = 80;
    my $store;

    my $silo_dir = "$dir/silo";

    eval { $store = Data::RecordStore::Silo->open_silo( 'A*', $silo_dir ); };
    like( $@, qr/annot open a zero/, 'tried to open zero store' );
    undef $@;
    ok( !( -e "$silo_dir/0" ), 'nothing created silo file created' );

    {
        local( $SIG{ __WARN__ } ) = $SIG{ __DIE__ };

        eval {$store = Data::RecordStore::Silo->open_silo( 'A*', $silo_dir, 199 ); };
        like( $@, qr/above the set max size/, 'got warning for opening a silo with a single record larger than the max size' );
        undef $@;
        ok( !( -e "$silo_dir/0" ), 'still nothing created silo file created' );
    }

    my $toobigdir = "$dir/toobig";
    eval {$store = Data::RecordStore::Silo->open_silo( 'A*', "$toobigdir", 199 ); };
    ok( ! $@, "no die for opening a store with a record larger than the max silo size (just a warning)" );
    ok( -e "$toobigdir/0", 'initial silo file created for toobig' );
    is( $store->[1], 199, "199 record size" );
    is( $store->[2], 199, "199 file size" );
    is( $store->[3], 1,  "1 max records per silo file" );


    my $cantdir = "$dir/cant";

    `touch $cantdir`;
    eval {$store = Data::RecordStore::Silo->open_silo( 'A*', "$cantdir", 30 ); };
    like( $@, qr/not a directory/, 'dies if directory is not a directory' );
    undef $@;

    `rm $cantdir`;
    `mkdir $cantdir`;

    `chmod a-w $cantdir`;

    eval {$store = Data::RecordStore::Silo->open_silo( 'A*', "$cantdir", 30 ); };
    like( $@, qr/Unable to open/, 'directory exists not writeable' );
    undef $@;

    $store = Data::RecordStore::Silo->open_silo( 'A*', $silo_dir, 20 );
    is( $store->[1], 20, "20 record size" );
    is( $store->[2], 80, "80 file size" );
    is( $store->[3], 4,  "4 max records per silo file" );

    $store = Data::RecordStore::Silo->open_silo( 'AAA', $silo_dir );
    is( $store->[1], 3, "record size 3" );

    eval {$store = Data::RecordStore::Silo->open_silo( 'AAA', $silo_dir, 30 ); };
    like( $@, qr/record size does not agree/, 'template and size given dont agree' );
    undef $@;

    $store = Data::RecordStore::Silo->open_silo( 'A*', $silo_dir, 30 );
    is( $store->[1], 30, "30 record size" );
    is( $store->[2], 60, "60 file size" );
    is( $store->[3], 2,  "2 max records per silo file" );

    $store = Data::RecordStore::Silo->open_silo( 'A*', $silo_dir, 41 );
    is( $store->[1], 41, "41 record size" );
    is( $store->[2], 41, "41 file size" );
    is( $store->[3], 1,  "1 max records per silo file" );

    $store = Data::RecordStore::Silo->open_silo( 'A*', $silo_dir, 20 );
    $store->_ensure_entry_count( 9 );

    my( @files ) = $store->_files;

    is( $store->[0], "$dir/silo", "directory" );
    is_deeply( \@files, [ 0, 1, 2 ], 'three silo files' );
    is( $store->entry_count, 9, "9 entries" );
    is( -s "$dir/silo/0", 80, "first file 80 bytes" );
    is( -s "$dir/silo/1", 80, "second file 80 bytes" );
    is( -s "$dir/silo/2", 20, "last file 20 bytes" );

    $store->empty;
    ok( -e "$dir/silo/0", "first file still exists" );
    is( -s "$dir/silo/0", 0, "first file zero bytes after empty" );
    ok( ! (-e "$dir/silo/1"), "second file gone" );
    ok( ! (-e "$dir/silo/2"), "third file gone" );

    $store->unlink_store;
    ok( ! (-e "$dir/silo"), "unlinked completely" );

} #test_open_silo

sub test_put_record {
    # actually open a silo

    my $dir = tempdir( CLEANUP => 1 );
    my $silo_dir = "$dir/silo";

    local $Data::RecordStore::Silo::MAX_SIZE = 80;

    my $store = Data::RecordStore::Silo->open_silo( 'A*', $silo_dir, 20 );

    # make sure 0 file was created
    ok( -e "$silo_dir/0", 'initial silo file created' );

    eval { $store->put_record( 0, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id too low' );
    undef $@;

    eval { $store->put_record( -1, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id way too low' );
    undef $@;

    eval { $store->put_record( 2, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id too high' );

    is( $store->entry_count, 0, "no entries yet" );

    eval { $store->put_record( 1, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id too high' );

    is( $store->entry_count, 0, "still no entries yet" );

    my $id = $store->next_id;
    is( $store->entry_count, 1, "first entry" );
    is( $id, 1, "first entry id" );

    # what happens if you try to write a record that is too big
    eval { $store->put_record( 1, "x" x 22 ); };
    like( $@, qr/record too large/, 'record too large' );

    eval { $store->put_record( 2, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id too high' );

    is_deeply( $store->get_record( 1 ), [''], "no data in first entry yet" );

    eval { $store->get_record( 2 ); };
    like( $@, qr/out of bounds/, 'id too high' );


    eval { $store->get_record( 0 ); };
    like( $@, qr/out of bounds/, 'id too low' );

    # test how many silo files are generated
    my( @files ) = $store->_files;
    is_deeply( \@files, [ 0 ], 'one silo file' );

    is( $store->[3], 4, 'four max records per silo file' );
    is( $store->[2], 80, '80 sized silo file' );

    $store->empty;

    local $Data::RecordStore::Silo::MAX_SIZE = 27; #3 records

    $store = Data::RecordStore::Silo->open_silo( 'IAI', $silo_dir );
    is( $store->[1], 9, "record size 9 bytes");
    $id = $store->next_id;
    is( $id, 1, "first id" );
    is( $store->entry_count, 1, "ec 1" );
    $store->put_record( 1, [ 43, "Q", 22 ] );
    is( -s "$silo_dir/0", 9, "file size now 9 bytes" );
    my $data = $store->get_record( 1 );
    is_deeply( $data, [  43, "Q", 22 ], 'correct data stored for first record' );
    is( $store->entry_count, 1, "ec still 1" );

    my $pop_data = $store->pop;
    is_deeply( $pop_data, $data, 'popped data is the first record' );
    is( $store->entry_count, 0, "ec back to 0" );
    $id = $store->next_id;
    is( $id, 1, "back to first id" );
    $store->pop;
    is( $store->entry_count, 0, "ec back to 0" );

    my $next_id = $store->push( [ 1, "A", 1001 ] );
    is( $next_id, 1, "pushed id" );
    $next_id = $store->push( [ 2, "b", 1001 ] );
    is( $next_id, 2, "pushed id" );
    $next_id = $store->push( [ 3, "c", 1001 ] );
    is( $next_id, 3, "pushed id" );
    $next_id = $store->push( [ 4, "D", 1001 ] );
    is( $next_id, 4, "pushed id" );

    is( $store->entry_count, 4, "now at 4 things" );
    is( -s "$silo_dir/0", 27, "first file now 27" );
    is( -s "$silo_dir/1", 9, "second file now 9" );

    is_deeply( $store->last_entry, [ 4, "D", 1001 ], "LAST ENTRY AGREES" );
    is( $store->entry_count, 4, "now at 4 things" );
    is( -s "$silo_dir/0", 27, "first file now 27" );
    is( -s "$silo_dir/1", 9, "second file now 9" );

    $data = $store->pop;
    is_deeply( $store->last_entry, [ 3, "c", 1001 ], "LAST ENTRY AGREES" );
    ok( !(-e "$silo_dir/1"), "second file removed" );
    is_deeply( $data, [ 4, "D", 1001 ], "pop 4" );

    $data = $store->pop;
    is_deeply( $store->last_entry, [ 2, "b", 1001 ], "LAST ENTRY AGREES" );
    is( -s "$silo_dir/0", 18, "first file smaller" );
    is_deeply( $data, [ 3, "c", 1001 ], "pop 3" );

    $data = $store->pop;
    is_deeply( $store->last_entry, [ 1, "A", 1001 ], "LAST ENTRY AGREES" );
    is( -s "$silo_dir/0", 9, "first file smaller" );
    is_deeply( $data, [ 2, "b", 1001 ], "pop 2" );

    $data = $store->pop;
    is( $store->last_entry, undef, "No last entry" );
    is( $store->entry_count, 0, "no entries after pop" );
    is( -s "$silo_dir/0", 0, "first file emptied" );
    ok( ! (-e "$silo_dir/1"), "no second file" );
    ok( ! (-e "$silo_dir/2"), "no third file" );
    is_deeply( $data, [ 1, "A", 1001 ], "pop 1" );

    # 3 records, 2 files
    $store->push( [ 1, "A", 1001 ] ); #0
    is( $store->entry_count, 1, "push 1" );
    $store->push( [ 22, "b", 10003 ] ); #1
    is( $store->entry_count, 2, "push 2" );
    $store->push( [ 333, "C", 10003 ] ); #2
    is( $store->entry_count, 3, "push 3" );
    $store->push( [ 4444, "d", 10003 ] ); #3
    is( $store->entry_count, 4, "push 4" );
    $store->push( [ 55555, "C", 10003 ] ); #4
    is( $store->entry_count, 5, "push 5" );

    eval { $store->_copy_record( 0, -1 ); };
    like( $@, qr/to_index -1 out of bounds/, 'to id too low' );
    undef $@;

    eval { $store->_copy_record( 0, 5 ); };
    like( $@, qr/to_index 5 out of bounds/, 'to id too high' );
    undef $@;

    eval { $store->_copy_record( -1, 0 ); };
    like( $@, qr/from_index -1 out of bounds/, 'from id too low' );
    undef $@;

    eval { $store->_copy_record( 5, 0 ); };
    like( $@, qr/from_index 5 out of bounds/, 'from id too high' );
    undef $@;


    $store->_copy_record( 3, 2 ); # idx used, not id like below
    is_deeply( $store->get_record( 4 ), [ 4444, "d", 10003 ], "record after copy" );
    is_deeply( $store->get_record( 3 ), [ 4444, "d", 10003 ], "copied record" );

} #test_put_record

sub test_broken_file {

    my $dir = tempdir( CLEANUP => 1 );
    my $silo_dir = "$dir/silo";

    local $Data::RecordStore::Silo::MAX_SIZE = 80;

    my $store = Data::RecordStore::Silo->open_silo( 'A*', $silo_dir, 20 );

    # make sure 0 file was created
    ok( -e "$silo_dir/0", 'initial silo file created' );

    $store->_ensure_entry_count( 4 );
    is( $store->entry_count, 4, "store has four entries" );
    my $next_id = $store->next_id;
    is( $next_id, 5, "next id is 5" );
    is( $store->entry_count, 5, "store has 5 entries" );

    my( @files ) = $store->_files;
    is_deeply( \@files, [ 0, 1 ], 'two silo files' );

    # break the last file here
    truncate "$store->[0]/1", 19; #remove the last byte from this record 'breaking' it
    is( $store->entry_count, 4, "entry count back down to 4" );
    $next_id = $store->next_id;
    is( $next_id, 5, "next id is again 5" );
    is( $store->entry_count, 5, "store back up to 5 entries" );

    # remove the last file and mess with the first one.
    unlink "$store->[0]/1";
    truncate "$store->[0]/0", 71;
    
    is( $store->entry_count, 3, "entry count back down to 3" );
    $next_id = $store->next_id;
    is( $next_id, 4, "next id is again 4" );

    
    
} #test_broken_file

__END__
