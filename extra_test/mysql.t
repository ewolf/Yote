#!/usr/bin/perl

use strict;
use warnings;

use Yote::WebAppServer;

use Yote::AppRoot;
use Yote::YoteRoot;
use Yote::IO::Mysql;
use Yote::IO::TestUtil;
use Yote::Test::TestAppNoLogin;
use Yote::Test::TestAppNeedsLogin;
use Yote::Test::TestDeepCloner;
use Yote::Test::TestNoDeepCloner;

use Data::Dumper;
use DBI;
use Test::More tests => 495;
use Test::Pod;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    for my $class (qw/Obj Hash IO::Mysql/) {
        use_ok( "Yote::$class" ) || BAIL_OUT( "Unable to load Yote::$class" );
    }
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

my( $host, $port, $store, $un, $pw ) = ( 'localhost', 27017, 'yote_test' );

print "Test Yote against mysql database up and running on $host : $port not requiring a username? ( Yes | No | Change Setup ) : ";
my $ans = <STDIN>;


if( $ans =~ /^\s*c/i ) {
    print "host [ $host ] : ";
    $ans = <STDIN>;
    chomp( $ans );
    $host ||= $ans;
    print "port [ $port ] : ";
    $ans = <STDIN>;
    chomp( $ans );
    $port ||= $ans;
    print "databasename [ $store ] : ";
    $ans = <STDIN>;
    chomp( $ans );
    $store ||= $ans;
    print "username : ";
    $ans = <STDIN>;
    chomp( $ans );
    if( $ans ) {
	$un = $ans;
	print "password : ";
	$ans = <STDIN>;
	chomp( $ans );
	$pw = $ans;
    }
}
elsif( $ans =~ /^\s*n/i ) {
    done_testing();    
    exit(0);
}

my %yote_args = ( 
    engine => 'mysql',
    host   => $host,
    engine_port => $port,
    store  => $store,
    );
if( $un ) {
    $yote_args{ user }       = $un;
    $yote_args{ password }   = $pw;
}

my $dbh = DBI->connect( "DBI:mysql:information_schema", $un, $pw );

$dbh->do( "DROP DATABASE $store" );
$dbh->do( "CREATE DATABASE $store" );

Yote::ObjProvider::init(
    %yote_args
    );

my $db = $Yote::ObjProvider::DATASTORE->database();
$db->do( "DROP TABLE objects" );
$db->do( "DROP TABLE field" );
$db->do( "DROP TABLE big_text" );
$Yote::ObjProvider::DATASTORE->ensure_datastore();
test_suite( $db );

done_testing();

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
    is( $o_count, 14, "number of objects before save root, since root is initiated automatically" );
    my $root = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    is( ref( $root ), 'Yote::YoteRoot', 'correct root class type' );
    ok( $root->{ID} == 1, "Root has id of 1" );
    my $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 14, "highest id in database is 14" );
    ( $o_count ) = query_line( $db, "SELECT count(*) FROM objects" );
    is( $o_count, 14, "number of objects after save root" ); # which also makes an account root automiatcially and has apps,emails,accounts,app_alias and library paths underneath it
    my( $f_count ) = query_line( $db, "SELECT count(*) FROM field" );
    is( $f_count, 11, "number of fields after yoteroot is called" );

#
# Save key value fields for simple scalars, arrays and hashes.
#                                                       # rows in fields total 
    $root->get_default( "DEFAULT" );                        # 1
    is( $root->set_first( "FRIST" ), "FRIST", "set returns value" );                            # 1
    $root->get_default_array( ["DEFAULT ARRAY"] );          # 2
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 15, "highest id in database 15" );
    $root->set_reallybig( "BIG" x 1.000);                    # 0
    $root->set_gross( 12 * 12 );                            # 1
    $root->set_array( ["THIS IS AN ARRAY"] );               # 2
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 16, "highest id in database 16" );
    $root->get_default_hash( { "DEFKEY" => "DEFVALUE" } );  # 2
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 17 , "highest id in database 17" );
    my $newo = new Yote::Obj();
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 18, "highest id in database 18" );
    my $somehash = {"preArray" => $newo};
    $newo->set_somehash( $somehash ); #testing for recursion
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 19, "highest id in database 19" );
    $root->get_cool_hash( { "llamapre" => ["prethis",$newo,$somehash] } );  # 2 (7 after stow all)
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 21, "highest id in database 21" );
    $root->set_hash( { "KEY" => "VALUE" } );                # 2
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 22, "highest id in database 22" );
    Yote::ObjProvider::stow_all();
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 22, "highest id in database still 22" );

    # added default_hash, { 'llama', ["this", new yote obj, "Array, and a new yote object bringing the object count to 7 + 6 = 13
    # the new max id should be 7 (root) + defalt_array 1,  array 1, default_hash 1, newobj 1, somehash 1, coolahash 1, arryincoolhash 1, hash 1
    $max_id = $Yote::ObjProvider::DATASTORE->max_id();
    is( $max_id, 22, "highest id in database is 22 after adding more objects" );
    Yote::ObjProvider::stow_all();
    # this resets the cool hash, overwriting what is there. 
    $root->set_cool_hash( { "llama" => ["this",new Yote::Obj(),{"Array",new Yote::Obj()}] } );  # 5 new objects
    Yote::ObjProvider::stow_all();
    my $recycled = $Yote::ObjProvider::DATASTORE->recycle_objects();
    is( $recycled, 4, "recycled 4 objects" );

    # the cool hash has been reset.  It has itself, an array, and newo and somehash inside it
    

# 1 from accounts under root (default)
# 1 from apps under root
# 1 from alias_apps
    my $db_rows = $db->selectall_arrayref("SELECT * FROM field");

    BAIL_OUT("error saving after stow all") unless is( scalar(@$db_rows), 39, "Number of db rows saved to database with stow all" );

    $db_rows = $db->selectall_arrayref("SELECT * FROM objects WHERE recycled=0");
    is( scalar(@$db_rows), 23, "Number of db rows saved to database not recycled" ); 
    $db_rows = $db->selectall_arrayref("SELECT * FROM objects WHERE recycled=1");
    is( scalar(@$db_rows), 4, "Number of db rows recycled" ); 

    Yote::IO::TestUtil::io_independent_tests( $root );
} #test suite

__END__
