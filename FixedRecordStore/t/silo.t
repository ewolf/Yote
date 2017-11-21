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

my $dir = tempdir( CLEANUP => 1 );

test_suite();

done_testing;

exit( 0 );


sub test_suite {

    $Data::RecordStore::Silo::MAX_SIZE = 80;

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

    eval {$store = Data::RecordStore::Silo->open_silo( 'A*', "$dir/toobig", 199 ); };
    ok( ! $@, "no die for opening a store with a record larger than the max silo size (just a warning)" );
    
    $store = Data::RecordStore::Silo->open_silo( 'A*', $silo_dir, 20 );

    # make sure 0 file was created
    ok( -e "$silo_dir/0", 'initial silo file created' );

    # what happens if you try to write a record that is too big
    eval { $store->put_record( 1, "x" x 22 ); };
    like( $@, qr/record too large/, 'record too large' );

    eval { $store->put_record( 0, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id too low' );
    undef $@;

    eval { $store->put_record( -1, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id way too low' );
    undef $@;

    eval { $store->put_record( 2, "x" x 2 ); };
    like( $@, qr/out of bounds/, 'id too high' );

    is( $store->entry_count, 0, "no entries yet" );

    my $id = $store->next_id;
    is( $store->entry_count, 1, "first entry" );
    is( $id, 1, "first entry id" );
    
    
} #test_record_silos

__END__
