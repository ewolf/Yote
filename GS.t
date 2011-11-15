#!/usr/bin/perl

use strict;

use Carp;

use GServ::ObjIO;
use GServ::AppProvider;

use Test::More;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN { 
    for my $class (qw/ObjIO Obj AppProvider Hash/) {
        use_ok( "GServ::$class" ) || BAIL_OUT( "Unable to load GServ::class" );
    }
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

#
# Create testing database, populate it with tables.
#
my $db = GServ::ObjIO::database();

sub query_line {
    my( $query, @args ) = @_;
    my( @ret ) = $db->selectrow_array( $query, {}, @args );
}

$db->do( "CREATE DATABASE IF NOT EXISTS sg_test" );
if( $db->errstr() ) {
    BAIL_OUT( $db->errstr() );
}
$db->do( "use sg_test" );
if( $db->errstr() ) {
    BAIL_OUT( $db->errstr() );
}
for my $table (qw/objects field big_text/) {
    $db->do( "CREATE TEMPORARY TABLE sg_test.$table LIKE sg.$table" );
    if( $db->errstr() ) {
        BAIL_OUT( $db->errstr() );
    }
}
pass( "created test database" );


# -----------------------------------------------------
#               start of gserv tests
# -----------------------------------------------------

                                         
#                                      #
# ----------- simple object tests -----#
#                                      #
my $root = GServ::AppProvider::fetch_root;
ok( $root->{ID} == 1, "Root has id of 1" );
my( $o_count ) = query_line( "SELECT count(*) FROM objects" );
is( $o_count, 1, "number of objects after save root" );
my( $f_count ) = query_line( "SELECT count(*) FROM field" );
is( $f_count, 0, "number of fields after save root" );


#
# Save key value fields for simple scalars, arrays and hashes.
#                                                       # rows in fields total to 12
$root->get_default( "DEFAULT" );                        # 1
$root->set_first( "FRIST" );                            # 1
$root->get_default_array( ["DEFAULT ARRAY"] );          # 2
$root->set_reallybig( "BIG" x 1000 );                   # 1
$root->set_gross( 12 * 12 );                            # 1 
$root->set_array( ["THIS IS AN ARRAY"] );               # 2
$root->get_default_hash( { "DEFKEY" => "DEFVALUE" } );  # 2
$root->set_hash( { "KEY" => "VALUE" } );                # 2
$root->save();

my $db_rows = $db->selectall_arrayref("SELECT * FROM field");
BAIL_OUT("error saving") unless is( scalar(@$db_rows), 12, "Number of db rows saved to database" );
my $root_clone = GServ::AppProvider::fetch_root;
is_deeply( $root_clone, $root, "CLONE to ROOT");
ok( $root_clone->{ID} == 1, "Reloaded Root has id of 1" );
is( $root_clone->get_default(), "DEFAULT", "get scalar with default" );
is( $root_clone->get_first(), "FRIST", "simple scalar" );
is( length($root_clone->get_reallybig()), length("BIG" x 1000), "Big String" );
is( $root_clone->get_gross(), 144, "simple number" );
is_deeply( $root_clone->get_default_array(), ["DEFAULT ARRAY"], "Simple default array" );
is_deeply( $root_clone->get_array(), ["THIS IS AN ARRAY"], "Simple array" );
is_deeply( $root_clone->get_default_hash(), {"DEFKEY"=>"DEFVALUE"}, "Simple default hash" );
my( %simple_hash ) = %{$root_clone->get_hash()};
is_deeply( \%simple_hash, {"KEY"=>"VALUE"}, "Simple hash" );

                                         
#                                      #
# ----------- deep container tests ----#
#                                      #

my $simple_array = $root->get_array();
push( @$simple_array, "With more than one thing" );
my $simple_hash = $root->get_hash();
$simple_hash->{FOO} = "bar";
$simple_hash->{BZAZ} = [ "woof", "bOOf" ];
$root->save();

#print STDERR Data::Dumper->Dump( [$db->selectall_arrayref("SELECT * FROM field ")] );

my $root_2 = GServ::AppProvider::fetch_root;
my( %simple_hash ) = %{$root_2->get_hash()};
delete $simple_hash{__ID__};
is_deeply( \%simple_hash, {"KEY"=>"VALUE","FOO" => "bar", BZAZ => [ "woof", "bOOf" ]}, "Simple hash after reload" );

is_deeply( $root, $root_2, "Root data after modifying array" );

my( %shh ) = %{$root_2->get_hash()};
delete $shh{__ID__};
is_deeply( \%shh, \%simple_hash, 'simple hash after second save' );
is_deeply( $simple_hash, $root_2->get_hash(), "the modified hash saved" );
is_deeply( $simple_array, $root_2->get_array(), "the modified array saved" );

$root->save();

#                                          #
# ----------- objects in objects tests ----#
#                                          #
$simple_hash->{BZAZ}[2] = $simple_hash;
my $new_obj = new GServ::Obj;
$new_obj->set_cow( "FIRSTY" );
$root->set_obj( $new_obj );
$root->add_to_array( "MORE STUFF" );
$root->add_to_array( "MORE STUFF" );
$root->save();

$simple_array = $root->get_array();
my $root_3 = GServ::AppProvider::fetch_root();
is_deeply( $root_3, $root, "recursive data structure" );

is_deeply( $root_3->get_obj(), $new_obj, "setting object" );

is( scalar(@$simple_array), 4, "add_to test array count" );
is_deeply( $root_3->get_array(), $simple_array, "add to test" );

$root->remove_from_array( "MORE STUFF" );
$root->save();

my $root_4 = GServ::AppProvider::fetch_root();

#                                          #
# ----------- parent child node tests -----#
#                                          #
my $is_child = GServ::AppProvider::a_child_of_b( $new_obj, $root );
ok( $is_child, "object child of root" );
my $is_child = GServ::AppProvider::a_child_of_b( $new_obj, $root_4 );
ok( $is_child, "object child of reloaded root" );


done_testing();
