#!/usr/bin/perl

use strict;

use Carp;

use GServ::ObjIO;
use GServ::MysqlIO;
use GServ::AppRoot;
use GServ::AppServer;

use Test::More;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    for my $class (qw/MysqlIO ObjIO Obj Hash/) {
        use_ok( "GServ::$class" ) || BAIL_OUT( "Unable to load GServ::class" );
    }
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

#
# Create testing database, populate it with tables.
#
GServ::ObjIO::init(
    datastore      => 'GServ::MysqlIO',
    );
my $db = $GServ::ObjIO::SINGLETON->database();

sub query_line {
    my( $query, @args ) = @_;
    my( @ret ) = $db->selectrow_array( $query, {}, @args );
}

if( 0 ) {
    $db->do( "CREATE DATABASE IF NOT EXISTS sg_test" );
    if( $db->errstr() ) {
	BAIL_OUT( $db->errstr() );
    }
}

$db->do( "use irrespon_test" );

if( $db->errstr() ) {
    BAIL_OUT( $db->errstr() );
}
for my $table (qw/objects field big_text/) {
    $db->do( "CREATE TEMPORARY TABLE irrespon_test.$table LIKE irrespon_sg.$table" );
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
my( $o_count ) = query_line( "SELECT count(*) FROM objects" );
is( $o_count, 0, "number of objects before save root" );
my $root = GServ::AppRoot::fetch_root();
ok( $root->{ID} == 1, "Root has id of 1" );
my( $o_count ) = query_line( "SELECT count(*) FROM objects" );
is( $o_count, 2, "number of objects after save root" ); # which also makes an account root automiatcially";
my( $f_count ) = query_line( "SELECT count(*) FROM field" );
is( $f_count, 1, "number of fields after save root" ); #1 for

#
# Save key value fields for simple scalars, arrays and hashes.
#                                                       # rows in fields total 
$root->get_default( "DEFAULT" );                        # 1
$root->set_first( "FRIST" );                            # 1
$root->get_default_array( ["DEFAULT ARRAY"] );          # 2
$root->set_reallybig( "BIG" x 1000 );                   # 1
$root->set_gross( 12 * 12 );                            # 1
$root->set_array( ["THIS IS AN ARRAY"] );               # 2
$root->get_default_hash( { "DEFKEY" => "DEFVALUE" } );  # 2
$root->get_cool_hash( { "llama" => ["this",new GServ::Obj(),{"Array",new GServ::Obj()}] } );  # 2 (6 after stow all)
$root->set_hash( { "KEY" => "VALUE" } );                # 2
$root->save();
# 1 from accounts under root (default)

my $db_rows = $db->selectall_arrayref("SELECT * FROM field");

BAIL_OUT("error saving") unless is( scalar(@$db_rows), 15, "Number of db rows saved to database with ordinary save" );

GServ::ObjProvider::stow_all();

my $db_rows = $db->selectall_arrayref("SELECT * FROM field");

BAIL_OUT("error saving after stow all") unless is( scalar(@$db_rows), 19, "Number of db rows saved to database with stow all" );

my $db_rows = $db->selectall_arrayref("SELECT * FROM objects");
is( scalar(@$db_rows), 12, "Number of db rows saved to database" ); #Big counts as obj


my $root_clone = GServ::AppRoot::fetch_root();

is( ref( $root_clone->get_cool_hash()->{llama} ), 'ARRAY', '2nd level array object' );
is( ref( $root_clone->get_account_root() ), 'GServ::Obj', '2nd level gserv object' );
is( ref( $root_clone->get_cool_hash()->{llama}->[2]->{Array} ), 'GServ::Obj', 'deep level gserv object in hash' );
is( ref( $root_clone->get_cool_hash()->{llama}->[1] ), 'GServ::Obj', 'deep level gserv object in array' );



is( ref( $root->get_cool_hash()->{llama} ), 'ARRAY', '2nd level array object (original root after save)' );
is( ref( $root->get_account_root() ), 'GServ::Obj', '2nd level gserv object  (original root after save)' );
is( ref( $root->get_cool_hash()->{llama}->[2]->{Array} ), 'GServ::Obj', 'deep level gserv object in hash  (original root after save)' );
is( ref( $root->get_cool_hash()->{llama}->[1] ), 'GServ::Obj', 'deep level gserv object in array (original root after save)' );


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

my $root_2 = GServ::AppRoot::fetch_root();
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
my $root_3 = GServ::AppRoot::fetch_root();
is_deeply( $root_3, $root, "recursive data structure" );

is_deeply( $root_3->get_obj(), $new_obj, "setting object" );

is( scalar(@$simple_array), 4, "add_to test array count" );
is_deeply( $root_3->get_array(), $simple_array, "add to test" );

$root->remove_from_array( "MORE STUFF" );
$root->save();

my $root_4 = GServ::AppRoot::fetch_root();

#                                          #
# ----------- parent child node tests -----#
#                                          #
my $is_child = GServ::ObjProvider::a_child_of_b( $new_obj, $root );
ok( $is_child, "object child of root" );
my $is_child = GServ::ObjProvider::a_child_of_b( $new_obj, $root_4 );
ok( $is_child, "object child of reloaded root" );

#
#                                          #
# ------------- app serv tests ------------#
#
#                                          #
my $root = GServ::AppRoot::fetch_root();
my $res = $root->process_command( { c => 'foo' } );
like( $res->{err}, qr/not found for app/i, "received error with bad command name" );
like( $root->process_command( { c => 'create_account'  } )->{err}, qr/no handle|password required/i, "no handle or password given for create account" );
like( $root->process_command( { c => 'create_account', d => {h => 'root'}  } )->{err}, qr/password required/i, "no password given for create account" );
like( $root->process_command( { c => 'create_account', d => {h => 'root', p => 'toor', e => 'foo@bar.com' }  } )->{r}, qr/created/i, "create account for root account" );
my $root_acct = GServ::ObjProvider::xpath("/handles/root");
unless( $root_acct ) {
    fail( "Root not loaded" );
    BAIL_OUT("cannot continue" );
}
is( GServ::ObjProvider::xpath_count("/handles"), 1, "1 handle stored");
is( $root_acct->get_handle(), 'root', 'handle set' );
is( $root_acct->get_email(), 'foo@bar.com', 'email set' );
is( $root_acct->get_password(), 'toor', 'password set' );
ok( $root_acct->get_is_root(), 'first account is root' );

like( $root->process_command( { c => 'create_account', d => {h => 'root', p => 'toor', e => 'baz@bar.com' }  } )->{err}, qr/handle already taken/i, "handle already taken" );
like( $root->process_command( { c => 'create_account', d => {h => 'toot', p => 'toor', e => 'foo@bar.com' }  } )->{err}, qr/email already taken/i, "email already taken" );
like( $root->process_command( { c => 'create_account', d => {h => 'toot', p => 'toor', e => 'baz@bar.com' }  } )->{r}, qr/created/i, "second account created" );
my $acct = GServ::ObjProvider::xpath("/handles/toot");
ok( ! $acct->get_is_root(), 'second account not root' );

# ------ hello app test -----
my $t = $root->process_command( { c => 'login', d => { h => 'toot', p => 'toor' } } );
ok( $t->{t}, "logged in with token $t->{t}" );
is( $root->process_command( { a => 'GServ::Hello', c => 'hello', d => { name => 'toot' }, t => $t->{t} } )->{r}, "hello there 'toot'. I have said hello 1 times.", "Hello app works with given token" );
my $as = new GServ::AppServer;
ok( $as, "GServ::AppServer compiles" );


my $root = GServ::AppRoot::fetch_root();


done_testing();

__END__
