#!/usr/bin/perl

use strict;
use warnings;

use Yote::AppRoot;
use Yote::Root;
use Yote::Test::TestAppNoLogin;
use Yote::Test::TestAppNeedsLogin;
use Yote::Test::TestDeepCloner;
use Yote::Test::TestNoDeepCloner;
use Yote::IO::YoteDB;
use Yote::IO::TestUtil;

use Data::Dumper;
use Devel::Refcount qw(refcount);
use Devel::FindRef;
use File::Temp qw/ :mktemp tempdir /;
use File::Spec::Functions qw( catdir updir );
use Test::More;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    for my $class (qw/Obj Hash IO::YoteDB WebAppServer/) {
        use_ok( "Yote::$class" ) || BAIL_OUT( "Unable to load Yote::$class" );
    }
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

my $dir = tempdir( CLEANUP => 1 );
Yote::ObjProvider::init( {
    engine => 'yotedb',
    store => $dir,
    } );
my $yotedb = $Yote::ObjProvider::DATASTORE;
test_suite( $yotedb );
done_testing();

exit( 0 );


sub test_suite {
    my $yotedb = shift;


# -----------------------------------------------------
#               start of yote tests
# -----------------------------------------------------


#                                      #
# ----------- simple object tests -----#
#                                      #
    my $ROOT_START = 24;

    my $fetched_root = Yote::Root->fetch_root();
    my $root = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );

    Yote::ObjProvider::stow_all();

    my $recycled = Yote::ObjProvider::recycle_objects();

    is( ref( $root ), 'Yote::Root', 'correct root class type' );
    ok( $root->{ID} == 1, "Root has id of 1" );
    is( $fetched_root, $root, "fetch_root works same as objprovider fetch" );

    my $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, $ROOT_START, "highest id in database is 1" );


#
# Save key value fields for simple scalars, arrays and hashes.
#                                                       # rows in fields total 
    $root->get_default( "DEFAULT" );                        # 1
    is( $root->set_first( "FRIST" ), "FRIST", "set_ returns value" ); # 1
    $root->get_default_array( ["DEFAULT ARRAY"] );          # 2
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, $ROOT_START + 1, "highest id in database 15" );
    $root->set_reallybig( "BIG" x 1.000);                    # 0
    $root->set_gross( 12 * 12 );                            # 1
    $root->set_array( ["THIS IS AN ARRAY"] );               # 2

    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, $ROOT_START+2, "highest id in database $ROOT_START + 2" );
    $root->get_default_hash( { "DEFKEY" => "DEFVALUE" } );  # 2
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, $ROOT_START+3, "highest id in database $ROOT_START+3" );
    my $newo = new Yote::Obj();

    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, $ROOT_START+4, "highest id in database $ROOT_START+4" );
    my $somehash = {"preArray" => $newo};

    $newo->set_somehash( $somehash ); #testing for recursion

    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, $ROOT_START+5, "highest id in database $ROOT_START+5" );
    $root->get_cool_hash( { "llamapre" => ["prethis",$newo,$somehash] } );  # 2 (7 after stow all)
    print STDERR Data::Dumper->Dump(["Newo $newo, somehash $somehash, llamapre ".$root->get_cool_hash()->{llamapre}.", cool_hash : " . $root->get_cool_hash()]);
    undef $newo;
    undef $somehash;

    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, $ROOT_START+7, "highest id in database $ROOT_START+7" );
    $root->set_hash( { "KEY" => "VALUE" } );                # 2
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, $ROOT_START+8, "highest id in database $ROOT_START+8" );
    Yote::ObjProvider::stow_all();



    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, $ROOT_START+8, "highest id in database still $ROOT_START+8" );

    # added default_hash, { 'llama', ["this", new yote obj, "Array, and a new yote object bringing the object count to 7 + 6 = 13
    # the new max id should be 7 (root) + defalt_array 1,  array 1, default_hash 1, newobj 1, somehash 1, coolahash 1, arryincoolhash 1, hash 1
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, $ROOT_START+8, "highest id in database is $ROOT_START+8 after adding more objects" );

    Yote::ObjProvider::stow_all();

    # get the ids, to see if those are avail after recycling
    my( %old_ids );
    {
        my $old_ch = $root->get_cool_hash();
        my $lpl    = $old_ch->{llamapre};
        my $ob    = $lpl->[1];
        my $sh    = $lpl->[2];
        (%old_ids) = map { Yote::ObjProvider::get_id($_) => 1 } ( $old_ch, $lpl, $ob, $sh );
    }

    # this resets the cool hash, overwriting what is there. 
    $root->set_cool_hash( { "llama" => ["this",new Yote::Obj(),{"Array",new Yote::Obj()}] } );  # 5 new objects

    Yote::ObjProvider::stow_all();
    $recycled = Yote::ObjProvider::recycle_objects();
    is( $recycled, 4, "recycled 4 objects" );

    my $recyc_ids = $Yote::ObjProvider::DATASTORE->get_recycled_ids;
    is( @$recyc_ids, 4, "four recycled ids" );
    for( @$recyc_ids ) {
        ok( $old_ids{ $_ }, "$_ was recycled" );
    }

    Yote::IO::TestUtil::io_independent_tests( $root );
} #test suite


__END__
