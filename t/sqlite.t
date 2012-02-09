#!/usr/bin/perl

use strict;

use Yote::WebAppServer;

use Yote::MysqlIO;
use Yote::AppRoot;
use Yote::Test::TestAppNoLogin;
use Yote::Test::TestAppNeedsLogin;
use Yote::SQLiteIO;

use Data::Dumper;
use File::Temp qw/ :mktemp /;
use File::Spec::Functions qw( catdir updir );
use Test::More;
use Test::Pod;


use vars qw($VERSION);
$VERSION = '0.01';

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    for my $class (qw/MysqlIO Obj Hash SQLiteIO/) {
        use_ok( "Yote::$class" ) || BAIL_OUT( "Unable to load Yote::class" );
    }
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

my( $fh, $name ) = mkstemp( "/tmp/SQLiteTest.XXXX" );
Yote::ObjProvider::init(
    datastore      => 'Yote::SQLiteIO',
    sqlitefile     => $name,
    );
my $db = $Yote::ObjProvider::DATASTORE->database();
$Yote::ObjProvider::DATASTORE->init_datastore();
test_suite( $db );

done_testing();

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
    my( $o_count ) = query_line( $db, "SELECT count(*) FROM objects" );
    is( $o_count, 0, "number of objects before save root" );
    my $root = Yote::AppRoot::fetch_root();
    ok( $root->{ID} == 1, "Root has id of 1" );
    my( $o_count ) = query_line( $db, "SELECT count(*) FROM objects" );
    is( $o_count, 1, "number of objects after save root" ); # which also makes an account root automiatcially";
    my( $f_count ) = query_line( $db, "SELECT count(*) FROM field" );
    is( $f_count, 0, "number of fields after save root" ); #0 for

#
# Save key value fields for simple scalars, arrays and hashes.
#                                                       # rows in fields total 
    $root->get_default( "DEFAULT" );                        # 1
    $root->set_first( "FRIST" );                            # 1
    $root->get_default_array( ["DEFAULT ARRAY"] );          # 2
    $root->set_reallybig( "BIG" x 1000);                   # 1
    $root->set_gross( 12 * 12 );                            # 1
    $root->set_array( ["THIS IS AN ARRAY"] );               # 2
    $root->get_default_hash( { "DEFKEY" => "DEFVALUE" } );  # 2
    $root->get_cool_hash( { "llama" => ["this",new Yote::Obj(),{"Array",new Yote::Obj()}] } );  # 2 (6 after stow all)
    $root->set_hash( { "KEY" => "VALUE" } );                # 2
    $root->save();
# 1 from accounts under root (default)

    my $db_rows = $db->selectall_arrayref("SELECT * FROM field");

    BAIL_OUT("error saving") unless is( scalar(@$db_rows), 14, "Number of db rows saved to database with ordinary save" );

    Yote::ObjProvider::stow_all();

    my $db_rows = $db->selectall_arrayref("SELECT * FROM field");

    BAIL_OUT("error saving after stow all") unless is( scalar(@$db_rows), 18, "Number of db rows saved to database with stow all" );

    my $db_rows = $db->selectall_arrayref("SELECT * FROM objects");
    is( scalar(@$db_rows), 11, "Number of db rows saved to database" ); #Big counts as obj


    my $root_clone = Yote::AppRoot::fetch_root();

    is( ref( $root_clone->get_cool_hash()->{llama} ), 'ARRAY', '2nd level array object' );
    is( ref( $root_clone->get_account_root() ), 'Yote::Obj', '2nd level yote object' );
    is( ref( $root_clone->get_cool_hash()->{llama}->[2]->{Array} ), 'Yote::Obj', 'deep level yote object in hash' );
    is( ref( $root_clone->get_cool_hash()->{llama}->[1] ), 'Yote::Obj', 'deep level yote object in array' );



    is( ref( $root->get_cool_hash()->{llama} ), 'ARRAY', '2nd level array object (original root after save)' );
    is( ref( $root->get_account_root() ), 'Yote::Obj', '2nd level yote object  (original root after save)' );
    is( ref( $root->get_cool_hash()->{llama}->[2]->{Array} ), 'Yote::Obj', 'deep level yote object in hash  (original root after save)' );
    is( ref( $root->get_cool_hash()->{llama}->[1] ), 'Yote::Obj', 'deep level yote object in array (original root after save)' );


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

    my $root_2 = Yote::AppRoot::fetch_root();
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
    my $new_obj = new Yote::Obj;
    $new_obj->set_cow( "FIRSTY" );
    $root->set_obj( $new_obj );
    $root->add_to_array( "MORE STUFF" );
    $root->add_to_array( "MORE STUFF" );
    $root->save();

    $simple_array = $root->get_array();
    my $root_3 = Yote::AppRoot::fetch_root();
    is_deeply( $root_3, $root, "recursive data structure" );

    is_deeply( $root_3->get_obj(), $new_obj, "setting object" );

    is( scalar(@$simple_array), 4, "add_to test array count" );

    is_deeply( $root_3->get_array(), $simple_array, "add to test" );

    $root->remove_from_array( "MORE STUFF" );
    $root->save();
    is( scalar(@$simple_array), 2, "add_to test array count after remove" );
    $root->remove_from_array( "MOREO STUFF" );
    $simple_array = $root_3->get_array();
    is( scalar(@$simple_array), 2, "add_to test array count after second remove" );

    my $root_4 = Yote::AppRoot::fetch_root();

#                                          #
# ----------- parent child node tests -----#
#                                          #
    my $is_child = Yote::ObjProvider::a_child_of_b( $new_obj, $root );
    ok( $is_child, "object child of root" );
    my $is_child = Yote::ObjProvider::a_child_of_b( $new_obj, $root_4 );
    ok( $is_child, "object child of reloaded root" );

#
#                                          #
# ------------- app serv tests ------------#
#
#                                          #
    my $root = Yote::AppRoot::fetch_root();
    my $res = $root->process_command( { c => 'foo' } );
    like( $res->{err}, qr/not found for app/i, "received error with bad command name" );
    like( $root->process_command( { c => 'create_account'  } )->{err}, qr/no handle|password required/i, "no handle or password given for create account" );
    like( $root->process_command( { c => 'create_account', d => {h => 'root'}  } )->{err}, qr/password required/i, "no password given for create account" );
    like( $root->process_command( { c => 'create_account', d => {h => 'root', p => 'toor', e => 'foo@bar.com' }  } )->{r}, qr/created/i, "create account for root account" );
    my $root_acct = Yote::ObjProvider::xpath("/handles/root");
    unless( $root_acct ) {
	fail( "Root not loaded" );
	BAIL_OUT("cannot continue" );
    }
    is( Yote::ObjProvider::xpath_count("/handles"), 1, "1 handle stored");
    is( $root_acct->get_handle(), 'root', 'handle set' );
    is( $root_acct->get_email(), 'foo@bar.com', 'email set' );
    not( $root_acct->get_password(), 'toor', 'password set' ); #password is encrypted
    ok( $root_acct->get_is_root(), 'first account is root' );

    like( $root->process_command( { c => 'create_account', d => {h => 'root', p => 'toor', e => 'baz@bar.com' }  } )->{err}, qr/handle already taken/i, "handle already taken" );
    like( $root->process_command( { c => 'create_account', d => {h => 'toot', p => 'toor', e => 'foo@bar.com' }  } )->{err}, qr/email already taken/i, "email already taken" );
    like( $root->process_command( { c => 'create_account', d => {h => 'toot', p => 'toor', e => 'baz@bar.com' }  } )->{r}, qr/created/i, "second account created" );
    my $acct = Yote::ObjProvider::xpath("/handles/toot");
    ok( ! $acct->get_is_root(), 'second account not root' );

# ------ hello app test -----
    my $t = $root->process_command( { c => 'login', d => { h => 'toot', p => 'toor' } } );
    ok( $t->{t}, "logged in with token $t->{t}" );
    is( $root->process_command( { a => 'Yote::Test::Hello', c => 'hello', d => { name => 'toot' }, t => $t->{t} } )->{r}, "hello there 'toot'. I have said hello 1 times.", "Hello app works with given token" );
    my $as = new Yote::WebAppServer;
    ok( $as, "Yote::WebAppServer compiles" );

#my $root = Yote::AppRoot::fetch_root();

    my $ta = new Yote::Test::TestAppNeedsLogin();
    my $aaa = $ta->get_array();
    my $resp = $ta->_obj_to_response( $aaa );
    is( $resp->{d}->[0], 'vA', 'fist el' );
    is( ref( $resp->{d}[1] ), 'HASH', 'second el hash' );
    my $ina = $resp->{d}[1]{d}{inner};
    is( $ina->{d}[0], "vJuan", "inner array el" );
    my $inh = $ina->{d}[1];
    is( ref( $inh ), 'HASH', 'inner hash' );
    is( $inh->{d}{peanut}, 'vButter', "scalar in inner hash" );
    my $ino = $inh->{d}{ego};
    ok( $ino > 0, "Inner object" );
    is( $resp->{d}[2], $ino, "3rd element outer array" );

} #test suite

__END__
