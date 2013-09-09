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
use Yote::MongoIO;

use Data::Dumper;
use File::Temp qw/ :mktemp /;
use File::Spec::Functions qw( catdir updir );
use Test::More tests => 212;
use Test::Pod;


use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    for my $class (qw/Obj Hash MongoIO/) {
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
# -----------------------------------------------------
#               start of yote tests
# -----------------------------------------------------


#                                      #
# ----------- simple object tests -----#
#                                      #
    is( $objcol->count(), 10, "number of objects after fetchroot" );
    my $root = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    is( ref( $root ), 'Yote::YoteRoot', 'correct root class type' );
    Yote::ObjProvider::stow_all();
    is( $objcol->count(), 10, "number of objects after save root" ); # which also makes an account root automiatcially and has apps,emails,accounts,app_alias and library paths underneath it

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
    is( $objcol->count(), 18, "number of objects after adding a bunch" );

    # this resets the cool hash, overwriting what is there, which was a hash, array, a new obj and a hash ( 4 things )
    $root->set_cool_hash( { "llama" => ["this",new Yote::Obj(),{"Array",new Yote::Obj()}] } );  # 5 new objects
    Yote::ObjProvider::stow_all();
    my $recycled = Yote::ObjProvider->recycle_objects();
    is( $recycled, 4, "recycled 4 objects" );
    Yote::ObjProvider::stow_all();
    is( $objcol->count(), 19, "number of objects after recycling" );



    my $root_clone = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    is( ref( $root_clone->get_cool_hash()->{llama} ), 'ARRAY', '2nd level array object' );
    is( ref( $root_clone->get_cool_hash()->{llama}->[2]->{Array} ), 'Yote::Obj', 'deep level yote object in hash' );
    is( ref( $root_clone->get_cool_hash()->{llama}->[1] ), 'Yote::Obj', 'deep level yote object in array' );



    is( ref( $root->get_cool_hash()->{llama} ), 'ARRAY', '2nd level array object (original root after save)' );
    is( ref( $root->get_cool_hash()->{llama}->[2]->{Array} ), 'Yote::Obj', 'deep level yote object in hash  (original root after save)' );
    is( ref( $root->get_cool_hash()->{llama}->[1] ), 'Yote::Obj', 'deep level yote object in array (original root after save)' );


    is_deeply( $root_clone, $root, "CLONE to ROOT");
    ok( $root_clone->{ID} eq Yote::ObjProvider::first_id(), "Reloaded Root has id of 1" );
    is( $root_clone->get_default(), "DEFAULT", "get scalar with default" );
    is( $root_clone->get_first(), "FRIST", "simple scalar" );
    is( length($root_clone->get_reallybig()), length("BIG" x 1.000), "Big String" );
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
    ok( !Yote::ObjProvider::__is_dirty( $clone_hash ), "hash not dirty" );
    is( ref(tied %$clone_hash),'Yote::Hash',"clone hash tied");
    # -- put
    $clone_hash->{fooh} = 'barh';
    ok( Yote::ObjProvider::__is_dirty( $clone_hash ), "Hash dirty after change" );
    my $fetched_hash = Yote::ObjProvider::fetch( $hid );
    is_deeply( $fetched_hash, { fooh => 'barh', KEY => 'VALUE' }, "hash after put" );
    is( $fetched_hash->{fooh}, 'barh', "changed hash works" );
    Yote::ObjProvider::stow( $fetched_hash );
    ok( !Yote::ObjProvider::__is_dirty( $clone_hash ), "hash not dirty after change and save" );
    # -- delete
    delete $clone_hash->{fooh};
    ok( Yote::ObjProvider::__is_dirty( $clone_hash ), "Hash dirty after delete" );
    $fetched_hash = Yote::ObjProvider::fetch( $hid );
    is_deeply( $fetched_hash, { KEY => 'VALUE' }, " hash after delete" );
    is( $fetched_hash->{fooh}, undef, " hash after deletion works" );
    Yote::ObjProvider::stow( $fetched_hash );
    ok( !Yote::ObjProvider::__is_dirty( $clone_hash ), "hash not dirty after delete and save" );
    # -- clear
    %$clone_hash = (); 
    ok( Yote::ObjProvider::__is_dirty( $clone_hash ), "Hash dirty after clear" );
    $fetched_hash = Yote::ObjProvider::fetch( $hid );
    is_deeply( $fetched_hash, {}, "Hash other reference also clear" );
    Yote::ObjProvider::stow( $fetched_hash );
    ok( !Yote::ObjProvider::__is_dirty( $clone_hash ), "Hash dirty after clear and save" );
    # -- reset simple hash
    $clone_hash->{KEY} = 'VALUE';

    #
    # Test dirtying of array. tests store, delete, clear, push, pop, shift, unshift, splice
    #
    my $def_arry = $root_clone->get_default_array();
    is_deeply( $def_arry, [ 'DEFAULT ARRAY' ], "default array def" );
    my $aid = Yote::ObjProvider::get_id( $def_arry );
    ok( !Yote::ObjProvider::__is_dirty( $def_arry ), "array not dirty" );
    is( ref(tied @$def_arry),'Yote::Array',"clone array tied");
    # - store
    $def_arry->[13] = "booya";  #14 
    $def_arry->[12] = "zoog";  
    ok( Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after store" );
    my $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ['DEFAULT ARRAY',(map { undef } (1..11)),'zoog','booya'], "array after store" );
    is( $fetched_arry->[12], 'zoog', 'changed array works after store');
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after store and save" );
    # - delete
    delete $def_arry->[12];
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ['DEFAULT ARRAY',(map { undef } (1..12)),'booya'], "array after delete" );
    ok( Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after delete" );
    ok( Yote::ObjProvider::__is_dirty( $fetched_arry ), "array dirty after delete" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after delete and save" );
    # - clear
    @{$def_arry} = ();
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry,[], "array after clear" );
    ok( Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after clear" );
    ok( Yote::ObjProvider::__is_dirty( $fetched_arry ), "array dirty after clear" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after clear and save" );
    # - push 
    push @$def_arry, "one", "two", "tree";
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ["one", "two", "tree"], "array after push" );
    ok( Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after push" );
    ok( Yote::ObjProvider::__is_dirty( $fetched_arry ), "array dirty after push" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after push and save" );    
    # - pop
    is( pop @$def_arry, "tree", "pop array value" );
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ["one", "two"], "array after pop" );
    ok( Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after pop" );
    ok( Yote::ObjProvider::__is_dirty( $fetched_arry ), "array dirty after pop" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after pop and save" );    
    # - shift
    is( shift @$def_arry, "one", "shifted array value" );
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ["two"], "array after shift" );
    ok( Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after shift" );
    ok( Yote::ObjProvider::__is_dirty( $fetched_arry ), "array dirty after shift" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after shift and save" );    
    # - unshift
    unshift @$def_arry, "newguy", "orange", "Lemon", "tango";
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ["newguy", "orange", "Lemon", "tango", "two"], "array after unshift" );
    ok( Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after unshift" );
    ok( Yote::ObjProvider::__is_dirty( $fetched_arry ), "array dirty after unshift" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after unshift and save" );    
    # - splice
    my( @slice ) = splice @$def_arry, 1, 2, "Booga", "Boo", "Bobby";
    is_deeply( \@slice, ["orange","Lemon"], "spliced array value" );
    $fetched_arry = Yote::ObjProvider::fetch( $aid );
    is_deeply( $fetched_arry, ["newguy", "Booga", "Boo", "Bobby", "tango","two"], "array after splice" );
    ok( Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after splice" );
    ok( Yote::ObjProvider::__is_dirty( $fetched_arry ), "array dirty after splice" );
    Yote::ObjProvider::stow( $fetched_arry );
    ok( !Yote::ObjProvider::__is_dirty( $def_arry ), "array dirty after splice and save" );    
    # - set in place
    my $last_set = $fetched_arry;
    @{$fetched_arry} = ("This Is","new");
    ok( Yote::ObjProvider::__is_dirty( $last_set ), "array dirty after set in place" );
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


    my $root_2 = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    ( %simple_hash ) = %{$root_2->get_hash()};
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
    $root->set_obj( $new_obj );
    $root->add_once_to_array( "MORE STUFF", "MORE STUFF", "MORE STUFF" );

    $root->add_once_to_obj_array( $new_obj, $new_obj );
    is( scalar(@{$root->get_obj_array()}), 1, "add once works for references" );

    $simple_array = $root->get_array();
    is( scalar(@$simple_array), 3, "add_once_to test array count" );

    $root->add_to_array( "MORE STUFF" );
    $root->add_to_array( "MORE STUFF", "MORE STUFF" );

    Yote::ObjProvider::stow_all();

    $simple_array = $root->get_array();
    my $root_3 = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    is_deeply( $root_3, $root, "recursive data structure" );

    is_deeply( $root_3->get_obj(), $new_obj, "setting object" );

    is( $root_3->count( 'array' ), 6, 'Array has 6 with count' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 3 } ), [ 'THIS IS AN ARRAY', 'With more than one thing', 'MORE STUFF' ], 'paginate limit 3' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 3, reverse => 1 } ), [ 'MORE STUFF', 'MORE STUFF', 'MORE STUFF' ], 'paginate reverse limit 3' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 1, skip => 2 } ), [ 'MORE STUFF' ], 'paginate limit 1 from 2' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 1, skip => 4, reverse => 1 } ), [ 'With more than one thing' ], 'paginate limit 1 from 4' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 3, skip => 4 } ), [ 'MORE STUFF','MORE STUFF' ], 'paginate limit 3 from 4' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 3, skip => 4, reverse => 1 } ), [ 'With more than one thing', 'THIS IS AN ARRAY' ], 'paginate limit 3 from 4 reversed' );

    # unified pagination test
    is_deeply( $root_3->_paginate( { name => 'array', limit => 3 } ), [ 'THIS IS AN ARRAY', 'With more than one thing', 'MORE STUFF' ], 'paginate with length limit' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 3, reverse => 1 } ), [ 'MORE STUFF', 'MORE STUFF', 'MORE STUFF' ], 'paginate reverse with length limit' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 1, skip => 2 } ), [ 'MORE STUFF' ], 'paginate with start and length' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 1, skip => 4, reverse => 1 } ), [ 'With more than one thing' ], 'paginate reverse with start and length' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 3, skip => 4 } ), [ 'MORE STUFF','MORE STUFF' ], 'paginate with start and length' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 3, skip => 4, reverse => 1  } ), [ 'With more than one thing', 'THIS IS AN ARRAY' ], 'paginate reverse with start and length' );
    is_deeply( $root_3->_paginate( { name => 'array', sort => 1 } ), [ 'MORE STUFF', 'MORE STUFF', 'MORE STUFF', 'MORE STUFF', 'THIS IS AN ARRAY', 'With more than one thing',  ], 'paginate with sort and no length limit' );
    is_deeply( $root_3->_paginate( { name => 'array', sort => 1, reverse => 1 } ), [ 'With more than one thing', 'THIS IS AN ARRAY',  'MORE STUFF', 'MORE STUFF', 'MORE STUFF', 'MORE STUFF',  ], 'paginate with reverse sort and no length limit' );
    is_deeply( $root_3->_paginate( { name => 'array', limit => 3, skip => 3, sort => 1 } ), [ 'MORE STUFF', 'THIS IS AN ARRAY', 'With more than one thing',  ], 'paginate with sort and no length limit' );

    is( scalar(@$simple_array), 6, "add_to test array count" );

    is_deeply( $root_3->get_array(), $simple_array, "add to test" );

    $root->remove_from_array( "MORE STUFF" );
    Yote::ObjProvider::stow_all();
    is( scalar(@$simple_array), 5, "add_to test array count after remove" );
    $root->remove_from_array( "MOREO STUFF" );
    $simple_array = $root_3->get_array();
    Yote::ObjProvider::stow_all();
    is( scalar(@$simple_array), 5, "add_to test array count after second remove" );
    $root->remove_all_from_array( "MORE STUFF" );
    Yote::ObjProvider::stow_all();
    $simple_array = $root_3->get_array();
    is_deeply( $root_3->get_array(), $simple_array, "add to test" );
    is( scalar(@$simple_array), 2, "add_to test array count after remove all" );

    $root->add_once_to_array( "MORE STUFF", "MORE STUFF 2", "MORE STUFF 3" );
    Yote::ObjProvider::stow_all();
    $simple_array = $root_3->get_array();
    is( scalar(@$simple_array), 5, "add_to test array count after remove all" );

    $root->remove_from_array( "MORE STUFF 3", "MORE STUFF", "MORE STUFF 2" );
    Yote::ObjProvider::stow_all();
    $simple_array = $root_3->get_array();
    is( scalar(@$simple_array), 2, "add_to test array count after remove all" );

    my $root_4 = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );


    # test shallow and deep clone.
    my $target_obj = new Yote::Obj();
    my $deep_cloner = new Yote::Test::TestDeepCloner();
    $deep_cloner->set_ref_to_clone( $target_obj );
    $deep_cloner->set_num_value( 1234 );
    $deep_cloner->set_array( [ "array", { of => "Awsome" } ] );
    $deep_cloner->set_hash( { "woot" => "Biza" } );
    $deep_cloner->set_txt_value( "This is text" );
    $deep_cloner->set_big_txt_value( "BIG" x 1.000 );
    $target_obj->set_deep_cloner( $deep_cloner );
    my $shallow_cloner = new Yote::Test::TestNoDeepCloner();    
    $target_obj->set_shallow_cloner( $shallow_cloner );
    my $arry = $target_obj->get_reftest([]);
    $target_obj->set_reftest2( $arry );
    push( @$arry, "FOO" );
    is_deeply( $target_obj->get_reftest2(), $target_obj->get_reftest(), "ref test equivalency" );
    ok( Yote::Obj::_is( $target_obj->get_reftest2(), $target_obj->get_reftest() ), "ref test yote identity 2" );
    is( ''.$target_obj->get_reftest2(), ''.$target_obj->get_reftest(), "thingy identity" );
    
    my $deep_clone = Yote::ObjProvider::power_clone( $target_obj );
    ok( $deep_clone->get_shallow_cloner()->_is( $shallow_cloner ), "deep clone did not clone NO CLONE object" );
    ok( ! $deep_clone->get_deep_cloner()->_is( $deep_cloner ), "did clone internal reference" );
    ok( $deep_clone->_is( $deep_clone->get_deep_cloner()->get_ref_to_clone() ), "deep clone replaces old reference with clone reference" );

    is_deeply( $deep_clone->get_deep_cloner()->get_array(), $deep_cloner->get_array(), "arrays are separate but identical" );
    ok( $deep_clone->get_deep_cloner()->get_array()->[1] ne $deep_cloner->get_array()->[1], "arrays are separate but identical" );
    is_deeply( $deep_clone->get_deep_cloner()->get_hash(), $deep_cloner->get_hash(), "hashes are separate but identical" );
    ok( $deep_clone->get_deep_cloner()->get_hash() ne $deep_cloner->get_hash(), "hashes are separate but identical" );
    

#
#                                          #
# ------------- app serv tests ------------#
#
#                                          #
    $root = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    Yote::ObjProvider::stow_all();
    eval { 
        $root->create_login();
        fail( "Able to create account without handle or password" );
    };
    like( $@, qr/no handle|password required/i, "no handle or password given for create account" );
    eval {
        $root->create_login( { h => 'root' } );
        fail( "Able to create account without password" );
    };
    like( $@, qr/password required/i, "no password given for create account " );
    my $res = $root->create_login( { h => 'root', p => 'toor', e => 'foo@bar.com' } );
    is( $res->{l}->get_handle(), 'root', "handle for created root account" );
    is( $res->{l}->get_email(), 'foo@bar.com', "handle for created root account" );
    Yote::ObjProvider::stow_all();
    my $root_acct = $root->_hash_fetch( "_handles", "root");
    unless( $root_acct ) {
        fail( "Root not loaded" );
        BAIL_OUT("cannot continue" );
    }
    is( $root->_count("_handles"), 1, "1 handle stored");
    is( $root_acct->get_handle(), 'root', 'handle set' );
    is( $root_acct->get_email(), 'foo@bar.com', 'email set' );
    isnt( $root_acct->get_password(), 'toor', 'password set' ); #password is encrypted
    ok( ! $root_acct->get__is_root(), 'first account is not root anyore' );

    eval {
        $root->create_login( { h => 'root', p => 'toor', e => 'baz@bar.com' } );
        fail( "Able to create login with same handle" );
    };
    like( $@, qr/handle already taken/i, "handle already taken" );
    eval {
        $root->create_login( { h => 'toot', p => 'toor', e => 'foo@bar.com' } );
        fail( "Able to create login with same email" );
    };
    like( $@, qr/email already taken/i, "email already taken" );
    $res = $root->create_login( { h => 'toot', p => 'toor', e => 'baz@bar.com' } );
    is( $res->{l}->get_handle(), 'toot', "second account created" );
    ok( $res->{t}, "second account created with token" );
    Yote::ObjProvider::stow_all();
    my $acct = $root->_hash_fetch( '_handles', 'toot' );
    ok( ! $acct->get__is_root(), 'second account not root' );

    my $rpass = Yote::ObjProvider::encrypt_pass( "realpass", 'realroot' );
    isnt( $rpass, "realpass", "password was encrypted" );
    $res = $root->_check_root( 'realroot', $rpass );
    eval {
	my $rrl = $root->login( { h => 'realroot', p => 'wrongpass' } );
    };
    like( $@, qr/incorrect login/i, "Wrong log in" );
    my $rrl = $root->login( { h => 'realroot', p => 'realpass' } );
    ok( $rrl->{t}, "Logged in got token" );

# ------ hello app test -----
    my $t = $root->login( { h => 'toot', p => 'toor' } );
    ok( $t->{t}, "Logged in got token" );
    ok( $t->{l}, "logged in with login object" );
    is( $t->{l}->get_handle(), 'toot', "logged in with login object with correct handle" );
    is( $t->{l}->get_email(), 'baz@bar.com', "logged in with login object with correct handle" );
    ok( $t->{t}, "logged in with token $t->{t}" );
    my( $hello_app ) = $root->fetch_app_by_class( 'Yote::Test::Hello' );
    is( $hello_app->hello( { name => 'toot' } ), "hello there 'toot'. I have said hello 1 times.", "Hello app works with given token" );
    my $as = new Yote::WebAppServer();
    ok( $as, "Yote::WebAppServer compiles" );


    my( $ta ) = $root->fetch_app_by_class( 'Yote::Test::TestAppNeedsLogin' );
    ok( $ta->get_yote_obj(), "test app created yote object automatically" );

    my $aaa = $ta->array( '', $t );


    is( $aaa->[0], 'A', 'first el' );
    is( ref( $aaa->[1] ), 'HASH', 'second el hash' );
    my $ina = $aaa->[1]{inner};
    is( $ina->[0], "Juan", "inner array el" );
    my $inh = $ina->[1];

    is( ref( $inh ), 'HASH', 'inner hash' );
    is( $inh->{peanut}, 'Butter', "scalar in inner hash" );
    my $ino = $inh->{ego};
    ok( $ino > 0, "Inner object" );
    is( $aaa->[2], $ino, "3rd element outer array" );


    $root->add_to_rogers( "an", "array", "test" );
    my $hf = $root->get_hashfoo( {} );
    $hf->{zort} = 'zot';

    $ta->give_obj( [ "Fooo obj" ], $acct );

    Yote::ObjProvider::stow_all();
    
    is( $root->_list_fetch( 'rogers', '1'), "array", "list_fetch with array" );
    is( $root->_hash_fetch( "hashfoo", "zort"), "zot", "hash_fetch with hash" );

    Yote::ObjProvider::stow_all();
    my $app = $root->_hash_fetch( '_apps', 'Yote::Test::TestAppNeedsLogin' );
    $app->add_to_azzy( "A","B","C","D");
    Yote::ObjProvider::stow_all();
    ok( ref( $app ) eq 'Yote::Test::TestAppNeedsLogin', "hash fetch gets AppObj" );
    is(  $app->_hash_fetch( 'azzy', '2' ), 'C', "hash fetch from AppRoot object" );
    is(  $app->_hash_fetch( 'azzy', '0' ), 'A', "hash fetch from AppRoot object" );

    # test hash fetch insert, _paginate 
    $res = $app->_paginate( { name => 'azzy' } );
    is_deeply( $res, [ qw/A B C D/ ], 'paginate list without limits correct' );
    $res = $app->_paginate( { name => 'azzy', limit => 2, skip => 0 } );
    is_deeply( $res, [ qw/A B/ ], 'paginate limits from 0 with 2 are correct' );
    $res = $app->_paginate( { name => 'azzy', limit => 2, skip => 1 } );
    is_deeply( $res, [ qw/B C/  ], 'paginate limits from 1 with 2 are correct' );
    $res = $app->_paginate( { name => 'azzy', limit => 2, skip => 4 } );
    is_deeply( $res, [ ], 'paginate limits beyond last index are empty' );

    $res = $app->_list_insert( 'azzy', 'E', 4 );

    # paginate_list
    $res = $app->_paginate( { name => 'azzy' } );
    is_deeply( $res, [ qw/A B C D E/ ], 'paginate list without limits correct' );
    $res = $app->_paginate( { name => 'azzy', limit => 2, skip => 4 } );
    is_deeply( $res, [ 'E' ], 'just the last of the paginate limit' );
    
    $res = $app->_paginate( { name => 'azzy', return_hash => 1 } );
    is_deeply( $res, { 0 => 'A', 1 => 'B', 2 => 'C', 3 => 'D', 4 => 'E' }, 'paginate hash without limits correct' );
    $res = $app->_paginate( { name => 'azzy', return_hash => 1, limit => 2, skip => 0 } );
    is_deeply( $res, { 0 => 'A', 1 => 'B' }, 'paginate list limits from 0 with 2 are correct' );
    $res = $app->_paginate( { name => 'azzy', return_hash => 1, limit => 2, skip => 4 } );
    is_deeply( $res, { 4 => 'E' }, 'just the last of the paginate limit returning hash' );
        
    $app->_list_delete( 'azzy', 2 );

    # paginate_hash
    $res = $app->_paginate( { name => 'azzy', return_hash => 1 } );
    is_deeply( $res, { 0 => 'A', 1 => 'B', 2 => 'D', 3 => 'E' }, 'paginate hash without limits correct after list_delete' );
    $res = $app->_paginate( { name => 'azzy' } );
    is_deeply( $res, [ qw/A B D E/ ], 'paginate list without limits correct after list_delete' );

    $app->_list_insert( 'azzy', 'foo/bar' );
    $res = $app->_paginate( { name => 'azzy' } );
    is_deeply( $res, [ qw(A B D E foo/bar ) ], 'added value with / in the name' );

    Yote::ObjProvider::stow_all();    

    my $hash = $app->get_hsh( {} );
    $hash->{'baz/bof'} = "FOOME";
    $hash->{Bingo} = "BARFO";
    Yote::ObjProvider::stow_all();
    $res = $app->_paginate( { name => 'hsh', return_hash => 1 } );
    is_deeply( $res, { 'baz/bof' => "FOOME", 'Bingo' => "BARFO" }, ' paginate for hash, with one key having a slash in its name' );

    # delete with key that has slash in the name
    $app->_hash_delete( 'hsh', 'baz/bof' );    
    $res = $app->_paginate( { name => 'hsh', return_hash => 1 } );
    is_deeply( $res, { 'Bingo' => "BARFO" }, 'delete with key having a slash in its name' );

    $app->_hash_insert( 'hsh', '/\\/yakk\\/zakk/bakk', 'gotta slashy for it' );
    $res = $app->_paginate( { name => 'hsh', return_hash => 1 } );
    is_deeply( $res, { 'Bingo' => "BARFO", '/\\/yakk\\/zakk/bakk' => 'gotta slashy for it' }, 'paginate for hash, with one key having a slash in its name' );

    # test hash argument to new obj :
    my $o = new Yote::Obj( { foof => "BARBARBAR", zeeble => [ 1, 88, { nine => "ten" } ] } );
    is( $o->get_foof(), "BARBARBAR", "obj hash constructore" );
    is( $o->get_zeeble()->[2]{nine}, "ten", 'obj hash constructor deep value' );
    
    # recursion testing
    my $o2 = new Yote::Obj( { recurse => $o } );
    $o->add_to_curse( $o2 );
    $o->set_emptylist( [] );
    $root->add_to_rogers( $o );
    Yote::ObjProvider::stow_all();
    is( $o->count( 'emptylist' ), 0, "emptylist" );

    # test hash argument to new obj :
    $o = new Yote::Obj( { foof => "BARBARBAR", zeeble => [ 1, 88, { nine => "ten" } ] } );
    is( $o->get_foof(), "BARBARBAR", "obj hash constructore" );
    is( $o->get_zeeble()->[2]{nine}, "ten", 'obj hash constructor deep value' );

    # recursion testing
    $o2 = new Yote::Obj( { recurse => $o } );
    $o->add_to_curse( $o2 );
    $o->set_emptylist( [] );
    $root->add_to_rogers( $o );
    Yote::ObjProvider::stow_all();
    is( $o->count( 'emptylist' ), 0, "emptylist" );

    $app->set_weirdy( $o );
    Yote::ObjProvider::stow_all();

    # test search_list
    $o->add_to_searchlist( new Yote::Obj( { n => "one", a => "foobie", b => "oobie", c => "goobol" } ),
			   new Yote::Obj( { n => "two", a => "bar", b => "car", c => "war" } ),
			   new Yote::Obj( { n => "three", c => "foobie", b => "xxx" } ),
			   new Yote::Obj( { n => "four", 'q' => "foobie", b => "xxx" } ),
			   new Yote::Obj( { n => "five", a => "foobie", b => "car", c => "war" } ),
	);
    Yote::ObjProvider::stow_all();

    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a' ], search_terms => [ 'foobie' ] } );
    is( @$res, 2, "Two search results" );
    my $searchlist = $o->get_searchlist();
    my %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 0, 4 );
    my %resids = map { $_->{ID} => 1 } @$res;
    is_deeply( \%ids, \%resids, "Got correct search matches" );

    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a', 'c' ], search_terms => [ 'foobie' ] } );
    is( @$res, 3, "Three search results" );
    %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 0, 2, 4 );
    %resids = map { $_->{ID} => 1 } @$res;
    is_deeply( \%ids, \%resids, "Got correct search matches" );

    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a', 'c' ], search_terms => [ 'foobie' ], limit => 2 } );
    is( @$res, 2, "Two paginated search results" );
    %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 0, 2 );
    %resids = map { $_->{ID} => 1 } @$res;
    is_deeply( \%ids, \%resids, "Got correct search matches. limited" );
    
    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a', 'c' ], search_terms => [ 'foobie' ], limit => 2, skip => 1 } );
    is( @$res, 2, "Two paginated search results" );
    %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 2, 4 );
    %resids = map { $_->{ID} => 1 } @$res;
    is_deeply( \%ids, \%resids, "Got correct search matches. paginated" );

    # paginate test of search
    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a' ], search_terms => [ 'foobie' ] } );
    is( @$res, 2, "Two search results" );
    $searchlist = $o->get_searchlist();
    %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 0, 4 );
    %resids = map { $_->{ID} => 1 } @$res;
    is_deeply( \%ids, \%resids, "Got correct search matches" );

    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a', 'c' ], search_terms => [ 'foobie' ] } );
    is( @$res, 3, "Three search results" );
    %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 0, 2, 4 );
    %resids = map { $_->{ID} => 1 } @$res;
    is_deeply( \%ids, \%resids, "Got correct search matches" );

    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a', 'c' ], search_terms => [ 'foobie' ], limit => 2 } );
    is( @$res, 2, "Two paginated search results" );
    %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 0, 2 );
    %resids = map { $_->{ID} => 1 } @$res;
    is_deeply( \%ids, \%resids, "Got correct search matches. limited" );
    
    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a', 'c' ], search_terms => [ 'foobie' ], limit => 2, skip => 1 } );
    is( @$res, 2, "Two paginated search results" );
    %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 2, 4 );
    %resids = map { $_->{ID} => 1 } @$res;
    is_deeply( \%ids, \%resids, "Got correct search matches. paginated" );


    $o->add_to_searchlist( new Yote::Obj( { n => "one", a => "aoobie", b => "oobie" } ) );
    Yote::ObjProvider::stow_all();

    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ] } );
    my @ids = map { $searchlist->[ $_ ]->{ID} } ( 4, 3, 5, 0, 2, 1 );
    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct sort order" );

    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ], reversed_orders => [ 1, 1 ] } );
    @ids = map { $searchlist->[ $_ ]->{ID} } reverse( 4, 3, 5, 0, 2, 1 );
    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct reversed sort order" );

    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ], reversed_orders => [ 0, 1 ] } );
    @ids = map { $searchlist->[ $_ ]->{ID} } ( 4, 3, 0, 5, 2, 1 );
    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct mixed sort order" );

    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ], limit => 3} );
    @ids = map { $searchlist->[ $_ ]->{ID} } ( 4, 3, 5 );

    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct limited sort order" );
    
    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ], limit => 4, skip => 2} );
    @ids = map { $searchlist->[ $_ ]->{ID} } ( 5, 0, 2, 1 );
    is( 4, @$res, "lim sort 4 results" );
    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct sort order pag" );

    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ], limit => 8, skip => 3 } );
    @ids = map { $searchlist->[ $_ ]->{ID} } ( 0, 2, 1 );
    is( 3, @$res, "pag sort 3 results" );
    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct pag sort order" );


    # paginate for sort
    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ] } );
    @ids = map { $searchlist->[ $_ ]->{ID} } ( 4, 3, 5, 0, 2, 1 );
    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct sort order" );

    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ], reversed_orders => [ 1, 1 ] } );
    @ids = map { $searchlist->[ $_ ]->{ID} } reverse( 4, 3, 5, 0, 2, 1 );
    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct reversed sort order" );

    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ], reversed_orders => [ 0, 1 ] } );
    @ids = map { $searchlist->[ $_ ]->{ID} } ( 4, 3, 0, 5, 2, 1 );
    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct mixed sort order" );

    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ], limit => 3 } );
    @ids = map { $searchlist->[ $_ ]->{ID} } ( 4, 3, 5 );
    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct limited sort order" );
    
    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ], limit => 4, skip => 2 } );
    @ids = map { $searchlist->[ $_ ]->{ID} } ( 5, 0, 2, 1 );
    is( 4, @$res, "lim sort 4 results" );
    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct sort order pag" );

    $res = $o->paginate( { name => 'searchlist', sort_fields => [ 'n', 'a' ], limit => 8, skip => 3 } );
    @ids = map { $searchlist->[ $_ ]->{ID} } ( 0, 2, 1 );
    is( 3, @$res, "pag sort 3 results" );
    is_deeply( \@ids, [ map { $_->{ID} } @$res ], "Got correct pag sort order" );


} #test suite

__END__
