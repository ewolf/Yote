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
use Yote::IO::Mongo;
use Yote::IO::TestUtil;

use Data::Dumper;
use File::Temp qw/ :mktemp /;
use File::Spec::Functions qw( catdir updir );
use Test::More;


use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    for my $class (qw/Obj Hash IO::Mongo/) {
        use_ok( "Yote::$class" ) || BAIL_OUT( "Unable to load Yote::$class" );
    }
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

my( $host, $port, $store, $un, $pw ) = ( 'localhost', 27017, 'yote_test' );
print "Test Yote against mongo database up and running on $host : $port not requiring a username? ( Yes | No | Change Setup ) : ";
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

my %client_args = (
    host=> $host,
    port=> $port,
    );
my %yote_args = ( 
    engine => 'mongo',
    host   => $host,
    engine_port => $port,
    store  => $store,
    );
if( $un ) {
    $client_args{ username } = $un;
    $client_args{ password } = $pw;
    $yote_args{ user }       = $un;
    $yote_args{ password }   = $pw;
}


my $client = MongoDB::MongoClient->new(
    %client_args
    );
my $db = $client->get_database( 'yote_test' );
$db->drop();
$db = $client->get_database( 'yote_test' );

Yote::ObjProvider::init(
    %yote_args
    );

$db = $Yote::ObjProvider::DATASTORE->database();
test_suite( $db );

done_testing();

exit( 0 );

sub test_suite {
    my $db = shift;
    my $objcol = $db->get_collection( "objects" );
    
    Yote::YoteRoot->fetch_root();
    my $ROOT_START = 20;

    is( $objcol->count(), $ROOT_START, "number of objects after fetchroot" );
    my $root = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    is( ref( $root ), 'Yote::YoteRoot', 'correct root class type' );
    Yote::ObjProvider::stow_all();
    is( $objcol->count(), $ROOT_START+3, "number of objects after save root" ); # which also makes an account root automiatcially and has apps,emails,accounts,app_alias and library paths underneath it

#
# Save key value fields for simple scalars, arrays and hashes.
#                                                       # Objects total
    $root->get_default( "DEFAULT" );                        # 
    $root->set_first( "FRIST" );                            # 
    $root->get_default_array( ["DEFAULT ARRAY"] );          # 8
    $root->set_reallybig( "BIG" x 1.000);                   # 0
    $root->set_gross( 12 * 12 );                            # 
    $root->set_array( ["THIS IS AN ARRAY"] );               # 9
    $root->get_default_hash( { "DEFKEY" => "DEFVALUE" } );  # 10

    my $newo = new Yote::Obj();                             # 11
    my $somehash = {"preArray" => $newo};
    $newo->set_somehash( $somehash );                       # 12 testing for recursion
    $root->get_cool_hash( { "llamapre" => ["prethis",$newo,$somehash] } );  # 14
    $root->set_hash( { "KEY" => "VALUE" } );                # 15
    Yote::ObjProvider::stow_all();
    is( $objcol->count(), $ROOT_START+11, "number of objects after adding a bunch" );

    # this resets the cool hash, overwriting what is there, which was a hash, array, a new obj and a hash ( 4 things )
    $root->set_cool_hash( { "llama" => ["this",new Yote::Obj(),{"Array",new Yote::Obj()}] } );  # 5 new objects
    Yote::ObjProvider::stow_all();
    my $recycled = Yote::ObjProvider->recycle_objects();
    is( $recycled, 4, "recycled 4 objects" );
    Yote::ObjProvider::stow_all();
    is( $objcol->count(), $ROOT_START+12, "number of objects after recycling" );

    Yote::IO::TestUtil::io_independent_tests( $root );
} #test suite

__END__
