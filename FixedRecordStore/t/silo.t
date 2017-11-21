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

} #test_put_record

__END__
