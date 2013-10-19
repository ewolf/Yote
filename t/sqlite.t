#!/usr/bin/perl

use strict;
use warnings;

use Yote::WebAppServer;

use Yote::AppRoot;
use Yote::YoteRoot;
use Yote::Test::TestAppNoLogin;
use Yote::Test::TestAppNeedsLogin;
use Yote::Test::TestDeepCloner;
use Yote::Test::TestNoDeepCloner;
use Yote::IO::SQLite;
use Yote::IO::TestUtil;

use Data::Dumper;
use File::Temp qw/ :mktemp /;
use File::Spec::Functions qw( catdir updir );
use Test::More tests => 486;
use Test::Pod;


use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    for my $class (qw/Obj Hash IO::SQLite/) {
        use_ok( "Yote::$class" ) || BAIL_OUT( "Unable to load Yote::$class" );
    }
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

my( $fh, $name ) = mkstemp( "/tmp/SQLiteTest.XXXX" );
$fh->close();

Yote::ObjProvider::init(
    datastore      => 'Yote::SQLiteIO',
    store          => $name,
    );
my $db = $Yote::ObjProvider::DATASTORE->database();
test_suite( $db );
done_testing();

unlink( $name );

exit( 0 );

sub query_line {
    my( $db, $query, @args ) = @_;
    my( @ret ) = $db->selectrow_array( $query, {}, @args );
}

sub test_suite {
    my $db = shift;


# -----------------------------------------------------
#               start of yote tests
# -----------------------------------------------------


#                                      #
# ----------- simple object tests -----#
#                                      #
    Yote::YoteRoot->fetch_root();
    my( $o_count ) = query_line( $db, "SELECT count(*) FROM objects" );
    is( $o_count, 13, "number of objects before save root, since root is initiated automatically" );
    my $root = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    is( ref( $root ), 'Yote::YoteRoot', 'correct root class type' );
    ok( $root->{ID} == 1, "Root has id of 1" );
    my $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 13, "highest id in database is 13" );
    ( $o_count ) = query_line( $db, "SELECT count(*) FROM objects" );
    is( $o_count, 13, "number of objects after save root" ); # which also makes an account root automiatcially and has apps,emails,accounts,app_alias and library paths underneath it as well as cron with a cron entry
    my( $f_count ) = query_line( $db, "SELECT count(*) FROM field" );
    is( $f_count, 10, "number of fields after yoteroot is called" );

#
# Save key value fields for simple scalars, arrays and hashes.
#                                                       # rows in fields total 
    $root->get_default( "DEFAULT" );                        # 1
    is( $root->set_first( "FRIST" ), "FRIST", "set_ returns value" ); # 1
    $root->get_default_array( ["DEFAULT ARRAY"] );          # 2
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 14, "highest id in database 14" );
    $root->set_reallybig( "BIG" x 1.000);                    # 0
    $root->set_gross( 12 * 12 );                            # 1
    $root->set_array( ["THIS IS AN ARRAY"] );               # 2
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 15, "highest id in database 15" );
    $root->get_default_hash( { "DEFKEY" => "DEFVALUE" } );  # 2
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 16, "highest id in database 16" );
    my $newo = new Yote::Obj();
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 17, "highest id in database 17" );
    my $somehash = {"preArray" => $newo};
    $newo->set_somehash( $somehash ); #testing for recursion
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 18, "highest id in database 18" );
    $root->get_cool_hash( { "llamapre" => ["prethis",$newo,$somehash] } );  # 2 (7 after stow all)
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 20, "highest id in database 20" );
    $root->set_hash( { "KEY" => "VALUE" } );                # 2
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 21, "highest id in database 21" );
    Yote::ObjProvider::stow_all();
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 21, "highest id in database still 21" );

    # added default_hash, { 'llama', ["this", new yote obj, "Array, and a new yote object bringing the object count to 7 + 6 = 13
    # the new max id should be 7 (root) + defalt_array 1,  array 1, default_hash 1, newobj 1, somehash 1, coolahash 1, arryincoolhash 1, hash 1
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 21, "highest id in database is 21 after adding more objects" );

    Yote::ObjProvider::stow_all();

    # this resets the cool hash, overwriting what is there. 
    $root->set_cool_hash( { "llama" => ["this",new Yote::Obj(),{"Array",new Yote::Obj()}] } );  # 5 new objects

    Yote::ObjProvider::stow_all();
    my $recycled = Yote::ObjProvider::recycle_objects();
    is( $recycled, 4, "recycled 4 objects" );

    # the cool hash has been reset.  It has itself, an array, and newo and somehash inside it
    

# 1 from accounts under root (default)
# 1 from apps under root
# 1 from alias_apps
    my $db_rows = $db->selectall_arrayref("SELECT * FROM field");

    BAIL_OUT("error saving after stow all") unless is( scalar(@$db_rows), 38, "Number of db rows saved to database with stow all" );

    $db_rows = $db->selectall_arrayref("SELECT * FROM objects WHERE recycled=0");
    is( scalar(@$db_rows), 22, "Number of db rows saved to database not recycled" ); 
    $db_rows = $db->selectall_arrayref("SELECT * FROM objects WHERE recycled=1");
    is( scalar(@$db_rows), 4, "Number of db rows recycled" ); 

    Yote::IO::TestUtil::io_independent_tests( $root );
} #test suite


__END__
