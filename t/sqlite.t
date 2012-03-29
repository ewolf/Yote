#!/usr/bin/perl

use strict;

use Yote::WebAppServer;

use Yote::MysqlIO;
use Yote::AppRoot;
use Yote::Test::TestAppNoLogin;
use Yote::Test::TestAppNeedsLogin;
use Yote::Test::TestDeepCloner;
use Yote::Test::TestNoDeepCloner;
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
        use_ok( "Yote::$class" ) || BAIL_OUT( "Unable to load Yote::$class" );
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
    my $root = Yote::AppRoot::_fetch_root();
    ok( $root->{ID} == 1, "Root has id of 1" );
    my( $o_count ) = query_line( $db, "SELECT count(*) FROM objects" );
    is( $o_count, 5, "number of objects after save root" ); # which also makes an account root automiatcially and has apps,emails,accounts and app_alias underneath it
    my( $f_count ) = query_line( $db, "SELECT count(*) FROM field" );
    is( $f_count, 0, "number of fields after save root" ); 

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
    Yote::ObjProvider::stow_all();
# 1 from accounts under root (default)
# 1 from apps under root
# 1 from alias_apps
    my $db_rows = $db->selectall_arrayref("SELECT * FROM field");

    BAIL_OUT("error saving after stow all") unless is( scalar(@$db_rows), 22, "Number of db rows saved to database with stow all" );

    my $db_rows = $db->selectall_arrayref("SELECT * FROM objects");
    is( scalar(@$db_rows), 15, "Number of db rows saved to database" ); #Big counts as obj


    my $root_clone = Yote::AppRoot::_fetch_root();
    is( ref( $root_clone->get_cool_hash()->{llama} ), 'ARRAY', '2nd level array object' );
    is( ref( $root_clone->_account_root() ), 'Yote::SystemObj', '2nd level yote object' );
    is( ref( $root_clone->get_cool_hash()->{llama}->[2]->{Array} ), 'Yote::Obj', 'deep level yote object in hash' );
    is( ref( $root_clone->get_cool_hash()->{llama}->[1] ), 'Yote::Obj', 'deep level yote object in array' );



    is( ref( $root->get_cool_hash()->{llama} ), 'ARRAY', '2nd level array object (original root after save)' );
    is( ref( $root->_account_root() ), 'Yote::SystemObj', '2nd level yote object  (original root after save)' );
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
    

    #
    # Test dirtying of hash. Tests if tied,  put, clear and delete
    #
    my $clone_hash = $root_clone->get_hash();
    is_deeply( $clone_hash, { KEY => 'VALUE' }, "hash def" );
    my $hid = Yote::ObjProvider::get_id( $clone_hash );
    ok( !Yote::ObjProvider::is_dirty( $clone_hash ), "hash not dirty" );
    is( ref(tied %$clone_hash),'Yote::Hash',"clone hash tied");
    # -- put
    $clone_hash->{fooh} = 'barh';
    ok( Yote::ObjProvider::is_dirty( $clone_hash ), "Hash dirty after change" );
    my $fetched_hash = Yote::ObjProvider::fetch( $hid );
    is_deeply( $fetched_hash, { fooh => 'barh', KEY => 'VALUE' }, "hash after put" );
    is( Yote::ObjProvider::row_size($fetched_hash), 2, "Size of hash by obj provider" );
    is( $fetched_hash->{fooh}, 'barh', "changed hash works" );
    Yote::ObjProvider::stow( $fetched_hash );
    ok( !Yote::ObjProvider::is_dirty( $clone_hash ), "hash not dirty after change and save" );
    # -- delete
    delete $clone_hash->{fooh};
    ok( Yote::ObjProvider::is_dirty( $clone_hash ), "Hash dirty after delete" );
    $fetched_hash = Yote::ObjProvider::fetch( $hid );
    is_deeply( $fetched_hash, { KEY => 'VALUE' }, " hash after delete" );
    is( $fetched_hash->{fooh}, undef, " hash after deletion works" );
    Yote::ObjProvider::stow( $fetched_hash );
    ok( !Yote::ObjProvider::is_dirty( $clone_hash ), "hash not dirty after delete and save" );
    # -- clear
    %$clone_hash = (); 
    ok( Yote::ObjProvider::is_dirty( $clone_hash ), "Hash dirty after clear" );
    $fetched_hash = Yote::ObjProvider::fetch( $hid );
    is_deeply( $fetched_hash, {}, "Hash other reference also clear" );
    Yote::ObjProvider::stow( $fetched_hash );
    ok( !Yote::ObjProvider::is_dirty( $clone_hash ), "Hash dirty after clear and save" );
    # -- reset simple hash
    $clone_hash->{KEY} = 'VALUE';

    #
    # Test dirtying of array. tests store, delete, clear, push, pop, shift, unshift, splice
    #
    my $def_arry = $root_clone->get_default_array();
    is_deeply( $def_arry, [ 'DEFAULT ARRAY' ], "default array def" );
    my $aid = Yote::ObjProvider::get_id( $def_arry );
    ok( !Yote::ObjProvider::is_dirty( $def_arry ), "array not dirty" );
    is( ref(tied @$def_arry),'Yote::Array',"clone array tied");
    # - store
    $def_arry->[13] = "booya";  #14 
    $def_arry->[12] = "zoog";  
    ok( Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after store" );
    my $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ['DEFAULT ARRAY',(map { undef } (1..11)),'zoog','booya'], "array after store" );
    is( $fetched_arry->[12], 'zoog', 'changed array works after store');
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after store and save" );
    # - delete
    delete $def_arry->[12];
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ['DEFAULT ARRAY',(map { undef } (1..12)),'booya'], "array after delete" );
    ok( Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after delete" );
    ok( Yote::ObjProvider::is_dirty( $fetched_arry ), "array dirty after delete" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after delete and save" );
    # - clear
    @{$def_arry} = ();
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry,[], "array after clear" );
    ok( Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after clear" );
    ok( Yote::ObjProvider::is_dirty( $fetched_arry ), "array dirty after clear" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after clear and save" );
    # - push 
    push @$def_arry, "one", "two", "tree";
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ["one", "two", "tree"], "array after push" );
    ok( Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after push" );
    ok( Yote::ObjProvider::is_dirty( $fetched_arry ), "array dirty after push" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after push and save" );    
    # - pop
    is( pop @$def_arry, "tree", "pop array value" );
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ["one", "two"], "array after pop" );
    ok( Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after pop" );
    ok( Yote::ObjProvider::is_dirty( $fetched_arry ), "array dirty after pop" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after pop and save" );    
    # - shift
    is( shift @$def_arry, "one", "shifted array value" );
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ["two"], "array after shift" );
    ok( Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after shift" );
    ok( Yote::ObjProvider::is_dirty( $fetched_arry ), "array dirty after shift" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after shift and save" );    
    # - unshift
    unshift @$def_arry, "newguy", "orange", "Lemon", "tango";
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ["newguy", "orange", "Lemon", "tango", "two"], "array after unshift" );
    ok( Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after unshift" );
    ok( Yote::ObjProvider::is_dirty( $fetched_arry ), "array dirty after unshift" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after unshift and save" );    
    # - splice
    my( @slice ) = splice @$def_arry, 1, 2, "Booga", "Boo", "Bobby";
    is_deeply( \@slice, ["orange","Lemon"], "spliced array value" );
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ["newguy", "Booga", "Boo", "Bobby", "tango","two"], "array after splice" );
    is( Yote::ObjProvider::row_size($fetched_arry), 6, "Size of array by obj provider" );
    ok( Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after splice" );
    ok( Yote::ObjProvider::is_dirty( $fetched_arry ), "array dirty after splice" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::is_dirty( $def_arry ), "array dirty after splice and save" );    
    # - set in place
    my $last_set = $fetched_arry;
    @{$fetched_arry} = ("This Is","new");
    ok( Yote::ObjProvider::is_dirty( $last_set ), "array dirty after set in place" );
    Yote::ObjProvider::stow( $fetched_arry );
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ["This Is","new"], "array after set in place" );
    

#                                      #
# ----------- deep container tests ----#
#                                      #

    my $simple_array = $root->get_array();
    push( @$simple_array, "With more than one thing" );
    my $simple_hash = $root->get_hash();
    $simple_hash->{FOO} = "bar";
    $simple_hash->{BZAZ} = [ "woof", "bOOf" ];
    Yote::ObjProvider::stow_all();

    my $root_2 = Yote::AppRoot::_fetch_root();
    my( %simple_hash ) = %{$root_2->get_hash()};
    delete $simple_hash{__ID__};
    is_deeply( \%simple_hash, {"KEY"=>"VALUE","FOO" => "bar", BZAZ => [ "woof", "bOOf" ]}, "Simple hash after reload" );

    is_deeply( $root, $root_2, "Root data after modifying array" );

    my( %shh ) = %{$root_2->get_hash()};
    delete $shh{__ID__};
    is_deeply( \%shh, \%simple_hash, 'simple hash after second save' );
    is_deeply( $simple_hash, $root_2->get_hash(), "the modified hash saved" );
    is_deeply( $simple_array, $root_2->get_array(), "the modified array saved" );

    Yote::ObjProvider::stow_all();

#                                          #
# ----------- objects in objects tests ----#
#                                          #
    $simple_hash->{BZAZ}[2] = $simple_hash;
    my $new_obj = new Yote::Obj;
    $new_obj->set_cow( "FIRSTY" );
    is( $new_obj->size(), 1, "Size of objects" );
    is( Yote::ObjProvider::row_size($new_obj), 1, "Size of objects by obj provider" );
    $root->set_obj( $new_obj );
    $root->add_to_array( "MORE STUFF" );
    $root->add_to_array( "MORE STUFF" );
    Yote::ObjProvider::stow_all();

    $simple_array = $root->get_array();
    my $root_3 = Yote::AppRoot::_fetch_root();
    is_deeply( $root_3, $root, "recursive data structure" );

    is_deeply( $root_3->get_obj(), $new_obj, "setting object" );

    is( scalar(@$simple_array), 4, "add_to test array count" );

    is_deeply( $root_3->get_array(), $simple_array, "add to test" );

    $root->remove_from_array( "MORE STUFF" );
    Yote::ObjProvider::stow_all();
    is( scalar(@$simple_array), 2, "add_to test array count after remove" );
    $root->remove_from_array( "MOREO STUFF" );
    $simple_array = $root_3->get_array();
    is( scalar(@$simple_array), 2, "add_to test array count after second remove" );

    my $root_4 = Yote::AppRoot::_fetch_root();


    # test shallow and deep clone.
    my $target_obj = new Yote::Obj();
    my $deep_cloner = new Yote::Test::TestDeepCloner();
    $deep_cloner->set_ref_to_clone( $target_obj );
    $deep_cloner->set_num_value( 1234 );
    $deep_cloner->set_array( [ "array", { of => "Awsome" } ] );
    $deep_cloner->set_hash( { "woot" => "Biza" } );
    $deep_cloner->set_txt_value( "This is text" );
    $deep_cloner->set_big_txt_value( "BIG" x 1000 );
    $target_obj->set_deep_cloner( $deep_cloner );
    my $shallow_cloner = new Yote::Test::TestNoDeepCloner();    
    $target_obj->set_shallow_cloner( $shallow_cloner );
    my $arry = $target_obj->get_reftest([]);
    $target_obj->set_reftest2( $arry );
    push( @$arry, "FOO" );
    is_deeply( $target_obj->get_reftest2(), $target_obj->get_reftest(), "ref test equivalency" );
    ok( Yote::Obj::is( $target_obj->get_reftest2(), $target_obj->get_reftest() ), "ref test yote identity 2" );
    is( ''.$target_obj->get_reftest2(), ''.$target_obj->get_reftest(), "thingy identity" );
    
    my $shallow_clone = $deep_cloner->clone();
    ok( $target_obj->is( $shallow_clone->get_ref_to_clone() ), "shallow clone did not clone reference" );
    is( $shallow_clone->get_big_txt_value(), "BIG" x 1000, "shallow clone got big text value" );
    is( $shallow_clone->get_txt_value(), "This is text", "shallow clone copied text" );
    is( $shallow_clone->get_num_value(), 1234, "shallow clone copied numbers" );
    is_deeply( $shallow_clone->get_array(), [ "array", { of => "Awsome" } ], "data structures in deep clone array" );
    is_deeply( $shallow_clone->get_hash(), { "woot" => "Biza" }, "data structures in deep clone hash" );
    is_deeply( $shallow_clone->get_array(), $deep_cloner->get_array(), "arrays are identical" );
    is_deeply( $shallow_clone->get_hash(), $deep_cloner->get_hash(), "hashes are identical" );
    $shallow_clone->set_big_txt_value("now I'm small");
    is( $deep_cloner->get_big_txt_value(), "BIG" x 1000, "changing big value on clone didn't change value on original." );

    my $deep_clone = Yote::ObjProvider::power_clone( $target_obj );
    ok( $deep_clone->get_shallow_cloner()->is( $shallow_cloner ), "deep clone did not clone NO CLONE object" );
    ok( ! $deep_clone->get_deep_cloner()->is( $deep_cloner ), "did clone internal reference" );
    ok( $deep_clone->is( $deep_clone->get_deep_cloner()->get_ref_to_clone() ), "deep clone replaces old reference with clone reference" );

    is_deeply( $deep_clone->get_deep_cloner()->get_array(), $deep_cloner->get_array(), "arrays are separate but identical" );
    ok( $deep_clone->get_deep_cloner()->get_array()->[1] ne $deep_cloner->get_array()->[1], "arrays are separate but identical" );
    is_deeply( $deep_clone->get_deep_cloner()->get_hash(), $deep_cloner->get_hash(), "hashes are separate but identical" );
    ok( $deep_clone->get_deep_cloner()->get_hash() ne $deep_cloner->get_hash(), "hashes are separate but identical" );
    

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
    my $root = Yote::AppRoot::_fetch_root();
    my $res = $root->_process_command( { c => 'foo' } );
    Yote::ObjProvider::stow_all();
    like( $res->{err}, qr/not found for app/i, "received error with bad command name" );
    like( $root->_process_command( { c => 'create_account'  } )->{err}, qr/no handle|password required/i, "no handle or password given for create account" );
    like( $root->_process_command( { c => 'create_account', data => {h => 'vroot'}  } )->{err}, qr/password required/i, "no password given for create account : " . $root->_process_command( { c => 'create_account', data => {h => 'vroot'}  } )->{err} );
    like( $root->_process_command( { c => 'create_account', data => {h => 'vroot', p => 'vtoor', e => 'vfoo@bar.com' }  } )->{r}, qr/created/i, "create account for root account" );
    Yote::ObjProvider::stow_all();
    my $root_acct = Yote::ObjProvider::xpath("/handles/root");
    unless( $root_acct ) {
        fail( "Root not loaded" );
        BAIL_OUT("cannot continue" );
    }
    is( Yote::ObjProvider::xpath_count("/handles"), 1, "1 handle stored");
    is( $root_acct->get_handle(), 'root', 'handle set' );
    is( $root_acct->get_email(), 'foo@bar.com', 'email set' );
    isnt( $root_acct->get_password(), 'toor', 'password set' ); #password is encrypted
    ok( $root_acct->get_is_root(), 'first account is root' );

    like( $root->_process_command( { c => 'create_account', data => {h => 'vroot', p => 'vtoor', e => 'vbaz@bar.com' }  } )->{err}, qr/handle already taken/i, "handle already taken" );
    like( $root->_process_command( { c => 'create_account', data => {h => 'vtoot', p => 'vtoor', e => 'vfoo@bar.com' }  } )->{err}, qr/email already taken/i, "email already taken" );
    like( $root->_process_command( { c => 'create_account', data => {h => 'vtoot', p => 'vtoor', e => 'vbaz@bar.com' }  } )->{r}, qr/created/i, "second account created" );
    my $acct = Yote::ObjProvider::xpath("/handles/toot");
    ok( ! $acct->get_is_root(), 'second account not root' );

# ------ hello app test -----
    my $t = $root->_process_command( { c => 'login', data => { h => 'vtoot', p => 'vtoor' } } );
    ok( $t->{t}, "logged in with token $t->{t}" );
    is( $root->_process_command( { a => 'Yote::Test::Hello', c => 'hello', data => { name => 'vtoot' }, t => $t->{t} } )->{r}, "vhello there 'toot'. I have said hello 1 times.", "Hello app works with given token" );
    my $as = new Yote::WebAppServer;
    ok( $as, "Yote::WebAppServer compiles" );


    my $ta = new Yote::Test::TestAppNeedsLogin();
    my $aaa = $ta->array();
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


    $root->add_to_foo( "an", "array", "test" );
    my $hf = $root->get_hashfoo( {} );
    $hf->{zort} = 'zot';

    Yote::ObjProvider::stow_all();

    is( Yote::ObjProvider::xpath("/foo/1"), "array", "xpath with array" );
    is( Yote::ObjProvider::xpath("/hashfoo/zort"), "zot", "xpath with array" );

    $root->_process_command( { c => 'get_app', a =>'Yote::Test::TestAppNeedsLogin' } );
    Yote::ObjProvider::stow_all();
    my $app = Yote::ObjProvider::xpath( '/apps/Yote::Test::TestAppNeedsLogin' );
    $app->add_to_azzy( "A","B","C","D");
    Yote::ObjProvider::stow_all();
    ok( ref( $app ) eq 'Yote::Test::TestAppNeedsLogin', "xpath gets AppObj" );
    is( $app->_xpath( '/azzy/2' ), 'C', "xpath from AppRoot object" );

} #test suite

__END__
