package Yote::IO::TestUtil;

use strict;
use warnings;

use vars qw($VERSION);

$VERSION = '0.001';

use Test::More;
use Yote::RootObj;
use Yote::Obj;
use Yote::UserObj;

use Aspect;

#
# To make the tests go faster and avoid having to use sleep for timing
# of the cron, override its _time function.
#
my $TIMEVAR;
after {
    my $t = defined( $TIMEVAR ) ? $TIMEVAR : time();
    $_->return_value( $t );
} call qr/_time/;


#
#
#
sub pass_permission {
    my( $obj, $acct, $cmd, $data, $msg ) = @_;
    eval {
	$obj->$cmd( $data, $acct );
    };
    my $err = $@;
    $err =~ s/at \/\S+\.pm.*//s;
    ok( $err eq '', $msg );
} #pass_permission

sub fail_permission {
    my( $obj, $acct, $cmd, $data, $msg ) = @_;
    eval {
	$obj->$cmd( $data, $acct );
    };
    my $err = $@;
    $err =~ s/ at \/\S+\.pm.*//s;
    ok( $err eq 'Access Error', $msg );
} #fail_permission

sub compare_sets {
    my( $s1, $s2, $msg ) = @_;
    is_deeply( [ scalar( @$s1 ), { map { $_ => 1 } @$s1 } ], [ scalar( @$s2 ), { map { $_ => 1 } @$s2 } ], $msg );
} #compare_sets

sub io_independent_tests {
    my( $root ) = @_;

    my $root_clone = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    is( ref( $root_clone->get_cool_hash()->{llama} ), 'ARRAY', '2nd level array object' );
    is( ref( $root_clone->get_cool_hash()->{llama}->[2]->{Array} ), 'Yote::Obj', 'deep level yote object in hash' );
    is( ref( $root_clone->get_cool_hash()->{llama}->[1] ), 'Yote::Obj', 'deep level yote object in array' );



    is( ref( $root->get_cool_hash()->{llama} ), 'ARRAY', '2nd level array object (original root after save)' );
    is( ref( $root->get_cool_hash()->{llama}->[2]->{Array} ), 'Yote::Obj', 'deep level yote object in hash  (original root after save)' );
    is( ref( $root->get_cool_hash()->{llama}->[1] ), 'Yote::Obj', 'deep level yote object in array (original root after save)' );


    is_deeply( $root_clone, $root, "CLONE to ROOT");
    ok( $root_clone->{ID} eq Yote::ObjProvider::first_id(), "Reloaded Root has first id" );
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
    is_deeply( $root_3->_paginate( { name => 'array', limit => 1, skip => 2 } ), [ 'MORE STUFF' ], 'paginate limit three from 2' );
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
    my $root_login = $root->_hash_fetch( "_handles", "root");
    my $root_acct = new Yote::Account( { login => $root_login } );
    

    unless( $root_login ) {
        fail( "Root not loaded" );
        BAIL_OUT("cannot continue" );
    }
    is( $root->_count("_handles"), 1, "1 handle stored");
    is( $root_login->get_handle(), 'root', 'handle set' );
    is( $root_login->get_email(), 'foo@bar.com', 'email set' );
    isnt( $root_login->get_password(), 'toor', 'password set' ); #password is encrypted    
    ok( ! $root_login->get__is_root(), 'first account is not root anyore' );

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
    my $login = $root->_hash_fetch( '_handles', 'toot' );
    my $acct = new Yote::Account( { login => $login } );
    ok( ! $login->get__is_root(), 'second account not root' );

    my $rpass = Yote::ObjProvider::encrypt_pass( "realpass", 'realroot' );
    isnt( $rpass, "realpass", "password was encrypted" );
    $res = $root->_update_master_root( 'realroot', $rpass );
    my $master_account = new Yote::Account( { login => $res } );
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

    $ta->give_obj( [ "Fooo obj" ], $login );

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

    $res = $app->_insert_at( 'azzy', 'E', 4 );

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
    is_deeply( $res, { 0 => 'A', 1 => 'B', 2 => 'D', 3 => 'E' }, 'paginate hash without limits correct after remove_from' );
    $res = $app->_paginate( { name => 'azzy' } );
    is_deeply( $res, [ qw/A B D E/ ], 'paginate list without limits correct after remove_from' );

    $app->_insert_at( 'azzy', 'foo/bar' );
    $res = $app->_paginate( { name => 'azzy' } );
    is_deeply( $res, [ qw(A B D E foo/bar ) ], 'added value with / in the name' );

    Yote::ObjProvider::stow_all();

    my $hash = $app->get_hsh( {} );
    $hash->{'baz/bof'} = "FOOME";
    $hash->{Bingo} = "BARFO";
    Yote::ObjProvider::stow_all();
    $res = $app->_paginate( { name => 'hsh', return_hash => 1 } );
    is_deeply( $res, { 'baz/bof' => "FOOME", 'Bingo' => "BARFO" }, ' paginate for hash, with one key having a slash in its name' );

    # test paginate with hashkey_search
    $res = $app->_paginate( { name => 'hsh', return_hash => 1, hashkey_search => [ "o" ] } );
    is_deeply( $res, { 'baz/bof' => "FOOME", 'Bingo' => "BARFO" }, ' paginate for hash using hashkey_search with one multiple hit search term' );

    $res = $app->_paginate( { name => 'hsh', return_hash => 1, hashkey_search => [ "B", '/' ] } );
    is_deeply( $res, { 'baz/bof' => "FOOME", 'Bingo' => "BARFO" }, ' paginate for hash using hashkey_search with two separate hit search terms' );

    $res = $app->_paginate( { name => 'hsh', return_hash => 1, hashkey_search => [ "g","Q" ] } );
    is_deeply( $res, { 'Bingo' => "BARFO" }, ' paginate for hash using hashkey_search with nonhit search term' );

    $res = $app->_paginate( { name => 'hsh', return_hash => 1, search_terms => [ "O" ] } );
    is_deeply( $res, { 'Bingo' => "BARFO" }, ' search_terms for hash using hashkey_search with nonhit search term' );

    $res = $app->_paginate( { name => 'hsh', return_hash => 1, search_terms => [ "O" ], hashkey_search => [ "" ] } );
    is_deeply( $res, { 'Bingo' => "BARFO" }, ' search_terms for hash using hashkey_search with nonhit search term' );

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

    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a' ], search_terms => [ 'foobie' ], sort_fields => [ 'n' ] } );
    is( @$res, 2, "Two search results" );
    $searchlist = $o->get_searchlist();
    %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 4, 0 );
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

    # paginate test of search
    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a' ], search_terms => [ 'foobie' ] } );
    is( @$res, 2, "Two search results" );
    $searchlist = $o->get_searchlist();
    %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 0, 4 );
    %resids = map { $_->{ID} => 1 } @$res;
    is_deeply( \%ids, \%resids, "Got correct search matches" );
    is( $o->count( { name => 'searchlist', search_fields => [ 'a' ], search_terms => [ 'foobie' ] } ), 2, "2 returned from count search" );
    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a', 'c' ], search_terms => [ 'foobie' ] } );
    is( @$res, 3, "Three search results" );
    %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 0, 2, 4 );
    %resids = map { $_->{ID} => 1 } @$res;
    is_deeply( \%ids, \%resids, "Got correct search matches" );

    is( $o->count( { name => 'searchlist', search_fields => [ 'a', 'c' ], search_terms => [ 'foobie' ] } ), 3, "3 returned from count search" );


    $res = $o->paginate( { name => 'searchlist', search_fields => [ 'a', 'c' ], search_terms => [ 'foobie' ], limit => 2 } );
    is( @$res, 2, "Two paginated search results" );
    %ids = map { $searchlist->[ $_ ]->{ID} => 1 } ( 0, 2 );
    %resids = map { $_->{ID} => 1 } @$res;
    is_deeply( \%ids, \%resids, "Got correct search matches. limited" );
    is( $o->count( { name => 'searchlist', search_fields => [ 'a', 'c' ], search_terms => [ 'foobie' ] } ), 3, "3 returned from count search" );

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

    # test add_to, count, delete_key, hash, insert_at, list_fetch, remove_from
    $o = new Yote::Obj( { anonymous => "guest" } );
    Yote::ObjProvider::stow_all();

    #set root back to root admin
    $root_login->set__is_root( 1 );

    #
    # Make sure named list operations properly integrate with recycling/garbage collection.
    #
    Yote::ObjProvider::recycle_objects();
    {
	my $o2a = new Yote::Obj( { name => "Test for list add to w/ recycling" } );
	my $o2b = new Yote::Obj( { name => "An other Test for list add to w/ recycling" } );
	$root->_add_to( 'o_list', $o2a );
	$root->_add_to( 'o_list', $o2b );
	Yote::ObjProvider::stow_all();
	is( $root->_container_type( 'o_list' ), 'ARRAY', 'container type detect list' );
	my $objs = Yote::ObjProvider::recycle_objects();
	is( $objs, 0, 'add_to(  not recycled' );
	$root->_remove_from( 'o_list', $o2a );
	$root->_remove_from( 'o_list', $o2b );
	Yote::ObjProvider::stow_all();
    }
    my $objs = Yote::ObjProvider::recycle_objects();
    is( $objs, 2, 'remove_from(  is recycled' );

    $root->set_o_list( undef );
    Yote::ObjProvider::stow_all();	
    is( Yote::ObjProvider::recycle_objects(), 1, "one recycled list obj" );
    is( $root->_container_type( 'o_list' ), '', 'container type detect no class once list removed' );

    {
	my $o2a = new Yote::Obj( { name => "yet Test for list add to w/ recycling" } );
	my $o2b = new Yote::Obj( { name => "yet An other Test for list add to w/ recycling" } );
	$root->_hash_insert( 'o_hash', "KEYA", $o2a );
	$root->_hash_insert( 'o_hash', "KEYB", $o2b );
	Yote::ObjProvider::stow_all();
	is( $root->_container_type( 'o_hash' ), 'HASH', 'container type detect hash' );
	my $objs = Yote::ObjProvider::recycle_objects();
	is( $objs, 0, 'hash(  not recycled' );
	$root->_hash_delete( 'o_hash', "KEYA" );
	$root->_hash_delete( 'o_hash', "KEYB" );
	Yote::ObjProvider::stow_all();	
    }
    $objs = Yote::ObjProvider::recycle_objects();
    is( $objs, 2, 'hash delete  is recycled' );

    $root->set_o_hash( undef );
    Yote::ObjProvider::stow_all();	
    is( $root->_container_type( 'o_hash' ), '', 'container type detect no class once hash removed' );

    $root->add_to( { name => 'z_list', items => [ "A", "B" ] }, $root_acct );
    is_deeply( $root->get_z_list(), [ "A", "B" ], "add to having correct obj" );

    $root->insert_at( { name => 'y_list', index => 2, item => "C" }, $root_acct );
    is_deeply( $root->get_y_list(), [ "C" ], "insert at to having correct obj" );

    $root->add_to( { name => 'el_list', items => [ "A", "B", $o ] }, $root_acct );
    $root->insert_at( { name => 'el_list', index => 0, item => "MrZERO" }, $root_acct );
    $root->insert_at( { name => 'el_list', index => 110, item => "MrEND" }, $root_acct );
    $root->add_to( { name => 'el_list', items => [ 'EVEN FURTHER' ] }, $root_acct );

    my $el_list = $root->get_el_list();
    is_deeply( $el_list, [ "MrZERO", "A", "B", $o, "MrEND", "EVEN FURTHER" ], "Add to and Insert At working" );

    # hash insert and hash delete key
    $root->hash( { name => 'el_hash', key => "FoO", value => "bAr" }, $root_acct );
    my $el_hash = $root->get_el_hash();
    is_deeply( $el_hash, { "FoO" => "bAr" }, 'hash method' );

    $root->_hash_insert( 'el_hash', 'BBB', 123 );
    is_deeply( $el_hash, { "FoO" => "bAr", "BBB" => 123 }, '_hash_insert method' );

    $root->_hash_delete( 'el_hash', 'FoO' );
    is_deeply( $el_hash, { 'BBB' => 123 }, "_hash_delete" );

    # root acct test
    my $new_master_login = $root->_update_master_root( "NEWROOT",Yote::ObjProvider::encrypt_pass( "NEWPW", "NEWROOT" ) );

    is( $new_master_login, $master_account->get_login(), "check root with new credentials does not change login" );

    # have $login, $root_login
    my $zoot_login = $root->create_login( { h => 'zoot', p => 'naughty', e => "zoot\@tooz.com" } )->{l};
    my $zoot_acct = new Yote::Account( { login => $zoot_login } );

    # test account enable disable
    my $login_test = $root->login( { h => 'zoot', p => 'naughty' } )->{l};
    ok( $login_test, "Login Test Zoot not disabled" );
    eval {
	$root->disable_login( $login_test, $zoot_acct ); 
    };
    like( $@, qr/Access Error/, "Need root to disable login" );
    $root->disable_login( $login_test, $root_acct ); 
    $login_test->set__is_disabled( 1 );
    eval {
	$login_test = $root->login( { h => 'zoot', p => 'naughty' } );
    };
    like( $@, qr/Access Error/, "Login disabling works" );
    eval {
	$root->enable_login( $login_test, $zoot_acct ); 
    };
    like( $@, qr/Access Error/, "Need root to enable login" );
    $root->enable_login( $login_test, $root_acct ); 
    $login_test = undef;
    $login_test = $root->login( { h => 'zoot', p => 'naughty' } )->{l};
    is( $login_test, $zoot_login, "Able to log in once reeanbled." );

    eval {
	$root->disable_login( $new_master_login, $root_acct ); 
    };
    like( $@, qr/Cannot disable master root login/, "cannot disable master root login" );

    eval {
	$root->disable_account( $master_account, $root_acct ); 
    };
    like( $@, qr/Cannot disable master root account/, "cannot disable master root account" );

    my $widget = $root->new_obj( { zip => 'zish' } );
    is( $widget->get_zip(), "zish", "root obj set something" );

    Yote::ObjManager::register_object( $widget->{ID}, $zoot_login->{ID} );
    Yote::ObjManager::register_object( $widget->{ID}, $root_login->{ID} );
    Yote::ObjManager::register_object( $widget->{ID}, $login->{ID} );

    compare_sets( Yote::ObjManager::fetch_dirty( $login ), [], "No dirty for acct" );
    compare_sets( Yote::ObjManager::fetch_dirty( $root_login ), [], "No dirty for root acct" );
    compare_sets( Yote::ObjManager::fetch_dirty( $zoot_login ), [], "No dirty for zoot acct" );

    $widget->set_thing( 22 );
    compare_sets( Yote::ObjManager::fetch_dirty( $login ), [ $widget->{ID}], "Missing dirty for acct" );
    compare_sets( Yote::ObjManager::fetch_dirty( $root_login ),  [ $widget->{ID} ], "Missing dirty for root acct" );
    compare_sets( Yote::ObjManager::fetch_dirty( $zoot_login ),  [ $widget->{ID} ], "Missing dirty for zoot acct" );

    compare_sets( Yote::ObjManager::fetch_dirty( $login ), [ ], "dirty cleared for acct" );
    compare_sets( Yote::ObjManager::fetch_dirty( $root_login ),  [ ], "dirty cleared for root acct" );
    compare_sets( Yote::ObjManager::fetch_dirty( $zoot_login ),  [ ], "dirty cleared for zoot acct" );

    my $mylist = $widget->set_mylist( [] );
    Yote::ObjManager::register_object( $widget->{DATA}{mylist}, $login->{ID} );
    $widget->_add_to( 'mylist', "A", 2, "Gamma" );
    
    compare_sets( Yote::ObjManager::fetch_dirty( $login ), [ $widget->{ID}, $widget->{DATA}{mylist} ], "_add_to makes dirty" );
    compare_sets( Yote::ObjManager::fetch_dirty( $login ), [  ], "dirty now cleaned" );

    is_deeply( $mylist, [ 'A', 2, 'Gamma' ], "list contents after add to" );

    $widget->_insert_at( 'mylist', "INTER", 1 );
    compare_sets( Yote::ObjManager::fetch_dirty( $login ), [ $widget->{DATA}{mylist} ], "_insert_at makes dirty" );
    compare_sets( Yote::ObjManager::fetch_dirty( $login ), [  ], "dirty now cleaned" );

    $widget->_remove_from( 'mylist', 2, 'A' );
    is_deeply( $mylist, [ "INTER", "Gamma" ], "_remove_from works" );
    compare_sets( Yote::ObjManager::fetch_dirty( $login ), [ $widget->{DATA}{mylist} ], "_remove_from makes dirty" );
    compare_sets( Yote::ObjManager::fetch_dirty( $login ), [  ], "dirty now cleaned" );

    $widget->_list_delete( 'mylist', 0 );
    is_deeply( $mylist, [ "Gamma" ], "_remove_from works" );
    compare_sets( Yote::ObjManager::fetch_dirty( $login ), [ $widget->{DATA}{mylist} ], "_list_delete makes dirty" );
    compare_sets( Yote::ObjManager::fetch_dirty( $login ), [  ], "dirty now cleaned" );


    #####################################################################################
    #										        #
    #   ----------------- permission tests on different object types. ----------------- #
    #   									        #
    #####################################################################################

    pass_permission( $widget, $root_acct, 'update', { baz_list => { 'hashfornow' => 12 }, zab_hash => {} }, 'Root may insert public var of plain obj' );
    pass_permission( $widget, $root_acct, 'update', { baz_list => [ 'bleqq' ], zab_hash => {} }, 'Root may update public var of plain obj' );
    pass_permission( $widget, $root_acct, 'update', { _baz_list => [ "bafff" ], _zab_hash => {}  }, 'Root may update private var of plain obj' );
    pass_permission( $widget, $root_acct, 'add_to', { name => '_baz_list', items => [ "one", "Item", "Now" ] }, 'Root may add_to private var of plain obj' );
    pass_permission( $widget, $root_acct, 'add_to', { name => 'baz_list', items => [ "one", "Item", "Now" ] }, 'Root may add_to public var of plain obj' );
    pass_permission( $widget, $root_acct, 'list_fetch', { name => '_baz_list', index => 1 }, 'Root may list_fetch private var of plain obj' );
    pass_permission( $widget, $root_acct, 'list_fetch', { name => 'baz_list', index => 1 }, 'Root may list_fetch public var of plain obj' );
    pass_permission( $widget, $root_acct, 'remove_from', { name => '_baz_list', items => [ 3, 5 ] }, 'Root may remove_from private var of plain obj' );
    pass_permission( $widget, $root_acct, 'remove_from', { name => 'baz_list', items => [ 3 ] }, 'Root may remove_from public var of plain obj' );
    pass_permission( $widget, $root_acct, 'paginate', { name => '_baz_list'}, 'Root may paginate private var of plain obj' );
    pass_permission( $widget, $root_acct, 'paginate', { name => 'baz_list'}, 'Root may paginate private var of plain obj' );
    pass_permission( $widget, $root_acct, 'list_fetch', { name => '_baz_list', index => 3 }, 'Root may list_fetch private var of plain obj' );
    pass_permission( $widget, $root_acct, 'list_fetch', { name => 'baz_list', index => 3 }, 'Root may list_fetch public var of plain obj' );
    pass_permission( $widget, $root_acct, 'list_delete', { name => 'baz_list', index => 3 }, 'Root may list_delete public var of plain obj' );
    pass_permission( $widget, $root_acct, 'list_delete', { name => '_baz_list', index => 3 }, 'Root may list_delete private var of plain obj' );
    pass_permission( $widget, $root_acct, 'insert_at', { name => '_baz_list', index => 3, item => "NAZ" }, 'Root may insert_at private var of plain obj' );
    pass_permission( $widget, $root_acct, 'insert_at', { name => 'baz_list', index => 3, item => "NAZ" }, 'Root may insert_at public var of plain obj' );
    pass_permission( $widget, $root_acct, 'count', { name => '_baz_list' }, 'Root may count private var of plain obj' );
    pass_permission( $widget, $root_acct, 'count', { name => 'baz_list' }, 'Root may count public var of plain obj' );

    pass_permission( $widget, $root_acct, 'hash', { name => '_zab_hash', key => "KY", value => "ValU" }, 'Root may hash private var of plain obj' );
    pass_permission( $widget, $root_acct, 'hash', { name => 'zab_hash', key => "KY", value => "ValU" }, 'Root may hash public var of plain obj' );
    pass_permission( $widget, $root_acct, 'delete_key', { name => 'zab_hash', key => "KY" }, 'Root may delete_key public var of plain obj' );
    pass_permission( $widget, $root_acct, 'delete_key', { name => '_zab_hash', key => "KY" }, 'Root may delete_key private var of plain obj' );

    pass_permission( $widget, $zoot_acct, 'update', { baz_list => [ 'bleqq' ], zab_hash => {} }, 'nonRoot may update public var of plain obj' );
    fail_permission( $widget, $zoot_acct, 'update', { _baz_list => [ "bafff" ], _zab_hash => {}  }, 'nonRoot may not update private var of plain obj' );
    fail_permission( $widget, $zoot_acct, 'add_to', { name => '_baz_list', items => [ "one", "Item", "Now" ] }, 'nonRoot may not add_to private var of plain obj' );
    pass_permission( $widget, $zoot_acct, 'add_to', { name => 'baz_list', items => [ "one", "Item", "Now" ] }, 'nonRoot may add_to public var of plain obj' );
    fail_permission( $widget, $zoot_acct, 'list_fetch', { name => '_baz_list', index => 1 }, 'nonRoot may not list_fetch private var of plain obj' );
    pass_permission( $widget, $zoot_acct, 'list_fetch', { name => 'baz_list', index => 1 }, 'nonRoot may list_fetch public var of plain obj' );
    fail_permission( $widget, $zoot_acct, 'remove_from', { name => '_baz_list', items => [ 3, 5 ] }, 'nonRoot may not remove_from private var of plain obj' );
    pass_permission( $widget, $zoot_acct, 'remove_from', { name => 'baz_list', items => [ 3 ] }, 'nonRoot may remove_from public var of plain obj' );
    fail_permission( $widget, $zoot_acct, 'paginate', { name => '_baz_list'}, 'nonRoot may not paginate private var of plain obj' );
    pass_permission( $widget, $zoot_acct, 'paginate', { name => 'baz_list'}, 'nonRoot may paginate private var of plain obj' );
    fail_permission( $widget, $zoot_acct, 'list_fetch', { name => '_baz_list', index => 3 }, 'nonRoot may not list_fetch private var of plain obj' );
    pass_permission( $widget, $zoot_acct, 'list_fetch', { name => 'baz_list', index => 3 }, 'nonRoot may list_fetch public var of plain obj' );
    pass_permission( $widget, $zoot_acct, 'list_delete', { name => 'baz_list', index => 3 }, 'nonRoot may list_delete public var of plain obj' );
    fail_permission( $widget, $zoot_acct, 'list_delete', { name => '_baz_list', index => 3 }, 'nonRoot may not list_delete private var of plain obj' );
    fail_permission( $widget, $zoot_acct, 'insert_at', { name => '_baz_list', index => 3, item => "NAZ" }, 'nonRoot may not insert_at private var of plain obj' );
    pass_permission( $widget, $zoot_acct, 'insert_at', { name => 'baz_list', index => 3, item => "NAZ" }, 'nonRoot may insert_at public var of plain obj' );
    fail_permission( $widget, $zoot_acct, 'count', { name => '_baz_list' }, 'nonRoot may not count private var of plain obj' );
    pass_permission( $widget, $zoot_acct, 'count', { name => 'baz_list' }, 'nonRoot may count public var of plain obj' );

    fail_permission( $widget, $zoot_acct, 'hash', { name => '_zab_hash', key => "KY", value => "ValU" }, 'nonRoot may not hash private var of plain obj' );
    pass_permission( $widget, $zoot_acct, 'hash', { name => 'zab_hash', key => "KY", value => "ValU" }, 'nonRoot may hash public var of plain obj' );
    pass_permission( $widget, $zoot_acct, 'delete_key', { name => 'zab_hash', key => "KY" }, 'nonRoot may delete_key public var of plain obj' );
    fail_permission( $widget, $zoot_acct, 'delete_key', { name => '_zab_hash', key => "KY" }, 'nonRoot may not delete_key private var of plain obj' );

    pass_permission( $widget, $acct, 'update', { baz_list => [ 'bleqq' ], zab_hash => {} }, 'other nonRoot may update public var of plain obj' );
    fail_permission( $widget, $acct, 'update', { _baz_list => [ "bafff" ], _zab_hash => {}  }, 'other nonRoot may not update private var of plain obj' );
    fail_permission( $widget, $acct, 'add_to', { name => '_baz_list', items => [ "one", "Item", "Now" ] }, 'other nonRoot may not add_to private var of plain obj' );
    pass_permission( $widget, $acct, 'add_to', { name => 'baz_list', items => [ "one", "Item", "Now" ] }, 'other nonRoot may add_to public var of plain obj' );
    fail_permission( $widget, $acct, 'list_fetch', { name => '_baz_list', index => 1 }, 'other nonRoot may not list_fetch private var of plain obj' );
    pass_permission( $widget, $acct, 'list_fetch', { name => 'baz_list', index => 1 }, 'other nonRoot may list_fetch public var of plain obj' );
    fail_permission( $widget, $acct, 'remove_from', { name => '_baz_list', items => [ 3, 5 ] }, 'other nonRoot may not remove_from private var of plain obj' );
    pass_permission( $widget, $acct, 'remove_from', { name => 'baz_list', items => [ 3 ] }, 'other nonRoot may remove_from public var of plain obj' );
    fail_permission( $widget, $acct, 'paginate', { name => '_baz_list'}, 'other nonRoot may not paginate private var of plain obj' );
    pass_permission( $widget, $acct, 'paginate', { name => 'baz_list'}, 'other nonRoot may paginate private var of plain obj' );
    fail_permission( $widget, $acct, 'list_fetch', { name => '_baz_list', index => 3 }, 'other nonRoot may not list_fetch private var of plain obj' );
    pass_permission( $widget, $acct, 'list_fetch', { name => 'baz_list', index => 3 }, 'other nonRoot may list_fetch public var of plain obj' );
    pass_permission( $widget, $acct, 'list_delete', { name => 'baz_list', index => 3 }, 'other nonRoot may list_delete public var of plain obj' );
    fail_permission( $widget, $acct, 'list_delete', { name => '_baz_list', index => 3 }, 'other nonRoot may not list_delete private var of plain obj' );
    fail_permission( $widget, $acct, 'insert_at', { name => '_baz_list', index => 3, item => "NAZ" }, 'other nonRoot may not insert_at private var of plain obj' );
    pass_permission( $widget, $acct, 'insert_at', { name => 'baz_list', index => 3, item => "NAZ" }, 'other nonRoot may insert_at public var of plain obj' );
    fail_permission( $widget, $acct, 'count', { name => '_baz_list' }, 'other nonRoot may not count private var of plain obj' );
    pass_permission( $widget, $acct, 'count', { name => 'baz_list' }, 'other nonRoot may count public var of plain obj' );

    fail_permission( $widget, $acct, 'hash', { name => '_zab_hash', key => "KY", value => "ValU" }, 'other nonRoot may not hash private var of plain obj' );
    pass_permission( $widget, $acct, 'hash', { name => 'zab_hash', key => "KY", value => "ValU" }, 'other nonRoot may hash public var of plain obj' );
    pass_permission( $widget, $acct, 'delete_key', { name => 'zab_hash', key => "KY" }, 'other nonRoot may delete_key public var of plain obj' );
    fail_permission( $widget, $acct, 'delete_key', { name => '_zab_hash', key => "KY" }, 'other nonRoot may not delete_key private var of plain obj' );


    my $root_widget = $root->new_root_obj( { zip => "zash" }, $root_acct );
    is( $root_widget->get_zip(), "zash", "root obj set something" );

    pass_permission( $root_widget, $root_acct, 'update', { baz_list => [ 'bleqq' ], zab_hash => {} }, 'Root may update public var of root obj' );
    pass_permission( $root_widget, $root_acct, 'update', { _baz_list => [ "bafff" ], _zab_hash => {}  }, 'Root may update private var of root obj' );
    pass_permission( $root_widget, $root_acct, 'add_to', { name => '_baz_list', items => [ "one", "Item", "Now" ] }, 'Root may add_to private var of root obj' );
    pass_permission( $root_widget, $root_acct, 'add_to', { name => 'baz_list', items => [ "one", "Item", "Now" ] }, 'Root may add_to public var of root obj' );
    pass_permission( $root_widget, $root_acct, 'list_fetch', { name => '_baz_list', index => 1 }, 'Root may list_fetch private var of root obj' );
    pass_permission( $root_widget, $root_acct, 'list_fetch', { name => 'baz_list', index => 1 }, 'Root may list_fetch public var of root obj' );
    pass_permission( $root_widget, $root_acct, 'remove_from', { name => '_baz_list', items => [ 3, 5 ] }, 'Root may remove_from private var of root obj' );
    pass_permission( $root_widget, $root_acct, 'remove_from', { name => 'baz_list', items => [ 3 ] }, 'Root may remove_from public var of root obj' );
    pass_permission( $root_widget, $root_acct, 'paginate', { name => '_baz_list'}, 'Root may paginate private var of root obj' );
    pass_permission( $root_widget, $root_acct, 'paginate', { name => 'baz_list'}, 'Root may paginate private var of root obj' );
    pass_permission( $root_widget, $root_acct, 'list_fetch', { name => '_baz_list', index => 3 }, 'Root may list_fetch private var of root obj' );
    pass_permission( $root_widget, $root_acct, 'list_fetch', { name => 'baz_list', index => 3 }, 'Root may list_fetch public var of root obj' );
    pass_permission( $root_widget, $root_acct, 'list_delete', { name => 'baz_list', index => 3 }, 'Root may list_delete public var of root obj' );
    pass_permission( $root_widget, $root_acct, 'list_delete', { name => '_baz_list', index => 3 }, 'Root may list_delete private var of root obj' );
    pass_permission( $root_widget, $root_acct, 'insert_at', { name => '_baz_list', index => 3, item => "NAZ" }, 'Root may insert_at private var of root obj' );
    pass_permission( $root_widget, $root_acct, 'insert_at', { name => 'baz_list', index => 3, item => "NAZ" }, 'Root may insert_at public var of root obj' );
    pass_permission( $root_widget, $root_acct, 'count', { name => '_baz_list' }, 'Root may count private var of root obj' );
    pass_permission( $root_widget, $root_acct, 'count', { name => 'baz_list' }, 'Root may count public var of root obj' );

    pass_permission( $root_widget, $root_acct, 'hash', { name => '_zab_hash', key => "KY", value => "ValU" }, 'Root may hash private var of root obj' );
    pass_permission( $root_widget, $root_acct, 'hash', { name => 'zab_hash', key => "KY", value => "ValU" }, 'Root may hash public var of root obj' );
    pass_permission( $root_widget, $root_acct, 'delete_key', { name => 'zab_hash', key => "KY" }, 'Root may delete_key public var of root obj' );
    pass_permission( $root_widget, $root_acct, 'delete_key', { name => '_zab_hash', key => "KY" }, 'Root may delete_key private var of root obj' );


    fail_permission( $root_widget, $zoot_acct, 'update', { baz_list => [ 'bleqq' ], zab_hash => {} }, 'nonRoot may not update public var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'update', { _baz_list => [ "bafff" ], _zab_hash => {}  }, 'nonRoot may not update private var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'add_to', { name => '_baz_list', items => [ "one", "Item", "Now" ] }, 'nonRoot may not add_to private var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'add_to', { name => 'baz_list', items => [ "one", "Item", "Now" ] }, 'nonRoot may not add_to public var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'list_fetch', { name => '_baz_list', index => 1 }, 'nonRoot may not list_fetch private var of root obj' );
    pass_permission( $root_widget, $zoot_acct, 'list_fetch', { name => 'baz_list', index => 1 }, 'nonRoot may list_fetch public var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'remove_from', { name => '_baz_list', items => [ 3, 5 ] }, 'nonRoot may not remove_from private var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'remove_from', { name => 'baz_list', items => [ 3 ] }, 'nonRoot may not remove_from public var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'paginate', { name => '_baz_list'}, 'nonRoot may not paginate private var of root obj' );
    pass_permission( $root_widget, $zoot_acct, 'paginate', { name => 'baz_list'}, 'nonRoot may paginate private var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'list_fetch', { name => '_baz_list', index => 3 }, 'nonRoot may not list_fetch private var of root obj' );
    pass_permission( $root_widget, $zoot_acct, 'list_fetch', { name => 'baz_list', index => 3 }, 'nonRoot may list_fetch public var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'list_delete', { name => 'baz_list', index => 3 }, 'nonRoot may not list_delete public var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'list_delete', { name => '_baz_list', index => 3 }, 'nonRoot may not list_delete private var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'insert_at', { name => '_baz_list', index => 3, item => "NAZ" }, 'nonRoot may not insert_at private var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'insert_at', { name => 'baz_list', index => 3, item => "NAZ" }, 'nonRoot may not insert_at public var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'count', { name => '_baz_list' }, 'nonRoot may not count private var of root obj' );
    pass_permission( $root_widget, $zoot_acct, 'count', { name => 'baz_list' }, 'nonRoot may count public var of root obj' );

    fail_permission( $root_widget, $zoot_acct, 'hash', { name => '_zab_hash', key => "KY", value => "ValU" }, 'nonRoot may not hash private var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'hash', { name => 'zab_hash', key => "KY", value => "ValU" }, 'nonRoot not may hash public var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'delete_key', { name => 'zab_hash', key => "KY" }, 'nonRoot may not delete_key public var of root obj' );
    fail_permission( $root_widget, $zoot_acct, 'delete_key', { name => '_zab_hash', key => "KY" }, 'nonRoot may not delete_key private var of root obj' );

    fail_permission( $root_widget, $acct, 'update', { baz_list => [ 'bleqq' ], zab_hash => {} }, 'other nonRoot may not update public var of root obj' );
    fail_permission( $root_widget, $acct, 'update', { _baz_list => [ "bafff" ], _zab_hash => {}  }, 'other nonRoot may not update private var of root obj' );
    fail_permission( $root_widget, $acct, 'add_to', { name => '_baz_list', items => [ "one", "Item", "Now" ] }, 'other nonRoot may not add_to private var of root obj' );
    fail_permission( $root_widget, $acct, 'add_to', { name => 'baz_list', items => [ "one", "Item", "Now" ] }, 'other nonRoot may not add_to public var of root obj' );
    fail_permission( $root_widget, $acct, 'list_fetch', { name => '_baz_list', index => 1 }, 'other nonRoot may not list_fetch private var of root obj' );
    pass_permission( $root_widget, $acct, 'list_fetch', { name => 'baz_list', index => 1 }, 'other nonRoot may list_fetch public var of root obj' );
    fail_permission( $root_widget, $acct, 'remove_from', { name => '_baz_list', items => [ 3, 5 ] }, 'other nonRoot may not remove_from private var of root obj' );
    fail_permission( $root_widget, $acct, 'remove_from', { name => 'baz_list', items => [ 3 ] }, 'other nonRoot may not remove_from public var of root obj' );
    fail_permission( $root_widget, $acct, 'paginate', { name => '_baz_list'}, 'other nonRoot may not paginate private var of root obj' );
    pass_permission( $root_widget, $acct, 'paginate', { name => 'baz_list'}, 'other nonRoot may paginate private var of root obj' );
    fail_permission( $root_widget, $acct, 'list_fetch', { name => '_baz_list', index => 3 }, 'other nonRoot may not list_fetch private var of root obj' );
    pass_permission( $root_widget, $acct, 'list_fetch', { name => 'baz_list', index => 3 }, 'other nonRoot may list_fetch public var of root obj' );
    fail_permission( $root_widget, $acct, 'list_delete', { name => 'baz_list', index => 3 }, 'other nonRoot may not list_delete public var of root obj' );
    fail_permission( $root_widget, $acct, 'list_delete', { name => '_baz_list', index => 3 }, 'other nonRoot may not list_delete private var of root obj' );
    fail_permission( $root_widget, $acct, 'insert_at', { name => '_baz_list', index => 3, item => "NAZ" }, 'other nonRoot may not insert_at private var of root obj' );
    fail_permission( $root_widget, $acct, 'insert_at', { name => 'baz_list', index => 3, item => "NAZ" }, 'other nonRoot may not insert_at public var of root obj' );
    fail_permission( $root_widget, $acct, 'count', { name => '_baz_list' }, 'other nonRoot may not count private var of root obj' );
    pass_permission( $root_widget, $acct, 'count', { name => 'baz_list' }, 'other nonRoot may count public var of root obj' );

    fail_permission( $root_widget, $acct, 'hash', { name => '_zab_hash', key => "KY", value => "ValU" }, 'other nonRoot may not hash private var of root obj' );
    fail_permission( $root_widget, $acct, 'hash', { name => 'zab_hash', key => "KY", value => "ValU" }, 'other nonRoot may not hash public var of root obj' );
    fail_permission( $root_widget, $acct, 'delete_key', { name => 'zab_hash', key => "KY" }, 'other nonRoot may not delete_key public var of root obj' );
    fail_permission( $root_widget, $acct, 'delete_key', { name => '_zab_hash', key => "KY" }, 'other nonRoot may not delete_key private var of root obj' );


    my $user_widget = $root->new_user_obj( { zip => "zash" }, $zoot_acct );
    is( $user_widget->get_zip(), "zash", "user obj set something" );

    pass_permission( $user_widget, $root_acct, 'update', { baz_list => [ 'bleqq' ], zab_hash => {} }, 'Root may update public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'update', { _baz_list => [ "bafff" ], _zab_hash => {}  }, 'Root may update private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'add_to', { name => '_baz_list', items => [ "one", "Item", "Now" ] }, 'Root may add_to private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'add_to', { name => 'baz_list', items => [ "one", "Item", "Now" ] }, 'Root may add_to public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_fetch', { name => '_baz_list', index => 1 }, 'Root may list_fetch private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_fetch', { name => 'baz_list', index => 1 }, 'Root may list_fetch public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'remove_from', { name => '_baz_list', items => [ 3, 5 ] }, 'Root may remove_from private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'remove_from', { name => 'baz_list', items => [ 3 ] }, 'Root may remove_from public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'paginate', { name => '_baz_list'}, 'Root may paginate private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'paginate', { name => 'baz_list'}, 'Root may paginate private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_fetch', { name => '_baz_list', index => 3 }, 'Root may list_fetch private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_fetch', { name => 'baz_list', index => 3 }, 'Root may list_fetch public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_delete', { name => 'baz_list', index => 3 }, 'Root may list_delete public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_delete', { name => '_baz_list', index => 3 }, 'Root may list_delete private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'insert_at', { name => '_baz_list', index => 3, item => "NAZ" }, 'Root may insert_at private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'insert_at', { name => 'baz_list', index => 3, item => "NAZ" }, 'Root may insert_at public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'count', { name => '_baz_list' }, 'Root may count private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'count', { name => 'baz_list' }, 'Root may count public var of user obj' );

    pass_permission( $user_widget, $root_acct, 'hash', { name => '_zab_hash', key => "KY", value => "ValU" }, 'Root may hash private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'hash', { name => 'zab_hash', key => "KY", value => "ValU" }, 'Root may hash public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'delete_key', { name => 'zab_hash', key => "KY" }, 'Root may delete_key public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'delete_key', { name => '_zab_hash', key => "KY" }, 'Root may delete_key private var of user obj' );

    pass_permission( $user_widget, $root_acct, 'update', { baz_list => [ 'bleqq' ], zab_hash => {} }, 'User Acct  may update public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'update', { _baz_list => [ "bafff" ], _zab_hash => {}  }, 'User Acct  may update private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'add_to', { name => '_baz_list', items => [ "one", "Item", "Now" ] }, 'User Acct  may add_to private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'add_to', { name => 'baz_list', items => [ "one", "Item", "Now" ] }, 'User Acct  may add_to public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_fetch', { name => '_baz_list', index => 1 }, 'User Acct  may list_fetch private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_fetch', { name => 'baz_list', index => 1 }, 'User Acct  may list_fetch public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'remove_from', { name => '_baz_list', items => [ 3, 5 ] }, 'User Acct  may remove_from private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'remove_from', { name => 'baz_list', items => [ 3 ] }, 'User Acct  may remove_from public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'paginate', { name => '_baz_list'}, 'User Acct  may paginate private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'paginate', { name => 'baz_list'}, 'User Acct  may paginate private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_fetch', { name => '_baz_list', index => 3 }, 'User Acct  may list_fetch private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_fetch', { name => 'baz_list', index => 3 }, 'User Acct  may list_fetch public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_delete', { name => 'baz_list', index => 3 }, 'User Acct  may list_delete public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'list_delete', { name => '_baz_list', index => 3 }, 'User Acct  may list_delete private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'insert_at', { name => '_baz_list', index => 3, item => "NAZ" }, 'User Acct  may insert_at private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'insert_at', { name => 'baz_list', index => 3, item => "NAZ" }, 'User Acct  may insert_at public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'count', { name => '_baz_list' }, 'User Acct  may count private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'count', { name => 'baz_list' }, 'User Acct  may count public var of user obj' );

    pass_permission( $user_widget, $root_acct, 'hash', { name => '_zab_hash', key => "KY", value => "ValU" }, 'User Acct  may hash private var of user obj' );
    pass_permission( $user_widget, $root_acct, 'hash', { name => 'zab_hash', key => "KY", value => "ValU" }, 'User Acct  may hash public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'delete_key', { name => 'zab_hash', key => "KY" }, 'User Acct  may delete_key public var of user obj' );
    pass_permission( $user_widget, $root_acct, 'delete_key', { name => '_zab_hash', key => "KY" }, 'User Acct  may delete_key private var of user obj' );

    fail_permission( $user_widget, $acct, 'update', { baz_list => [ 'bleqq' ], zab_hash => {} }, 'other nonRoot may not update public var of user obj' );
    fail_permission( $user_widget, $acct, 'update', { _baz_list => [ "bafff" ], _zab_hash => {}  }, 'other nonRoot may not update private var of user obj' );
    fail_permission( $user_widget, $acct, 'add_to', { name => '_baz_list', items => [ "one", "Item", "Now" ] }, 'other nonRoot may not add_to private var of user obj' );
    fail_permission( $user_widget, $acct, 'add_to', { name => 'baz_list', items => [ "one", "Item", "Now" ] }, 'other nonRoot may not add_to public var of user obj' );
    fail_permission( $user_widget, $acct, 'list_fetch', { name => '_baz_list', index => 1 }, 'other nonRoot may not list_fetch private var of user obj' );
    pass_permission( $user_widget, $acct, 'list_fetch', { name => 'baz_list', index => 1 }, 'other nonRoot may list_fetch public var of user obj' );
    fail_permission( $user_widget, $acct, 'remove_from', { name => '_baz_list', items => [ 3, 5 ] }, 'other nonRoot may not remove_from private var of user obj' );
    fail_permission( $user_widget, $acct, 'remove_from', { name => 'baz_list', items => [ 3 ] }, 'other nonRoot may not remove_from public var of user obj' );
    fail_permission( $user_widget, $acct, 'paginate', { name => '_baz_list'}, 'other nonRoot may not paginate private var of user obj' );
    pass_permission( $user_widget, $acct, 'paginate', { name => 'baz_list'}, 'other nonRoot may paginate private var of user obj' );
    fail_permission( $user_widget, $acct, 'list_fetch', { name => '_baz_list', index => 3 }, 'other nonRoot may not list_fetch private var of user obj' );
    pass_permission( $user_widget, $acct, 'list_fetch', { name => 'baz_list', index => 3 }, 'other nonRoot may list_fetch public var of user obj' );
    fail_permission( $user_widget, $acct, 'list_delete', { name => 'baz_list', index => 3 }, 'other nonRoot may not list_delete public var of user obj' );
    fail_permission( $user_widget, $acct, 'list_delete', { name => '_baz_list', index => 3 }, 'other nonRoot may not list_delete private var of user obj' );
    fail_permission( $user_widget, $acct, 'insert_at', { name => '_baz_list', index => 3, item => "NAZ" }, 'other nonRoot may not insert_at private var of user obj' );
    fail_permission( $user_widget, $acct, 'insert_at', { name => 'baz_list', index => 3, item => "NAZ" }, 'other nonRoot may not insert_at public var of user obj' );
    fail_permission( $user_widget, $acct, 'count', { name => '_baz_list' }, 'other nonRoot may not count private var of user obj' );
    pass_permission( $user_widget, $acct, 'count', { name => 'baz_list' }, 'other nonRoot may count public var of user obj' );

    fail_permission( $user_widget, $acct, 'hash', { name => '_zab_hash', key => "KY", value => "ValU" }, 'other nonRoot may not hash private var of user obj' );
    fail_permission( $user_widget, $acct, 'hash', { name => 'zab_hash', key => "KY", value => "ValU" }, 'other nonRoot may not hash public var of user obj' );
    fail_permission( $user_widget, $acct, 'delete_key', { name => 'zab_hash', key => "KY" }, 'other nonRoot may not delete_key public var of user obj' );
    fail_permission( $user_widget, $acct, 'delete_key', { name => '_zab_hash', key => "KY" }, 'other nonRoot may not delete_key private var of user obj' );

    # cron tests
    my $cron = $root->get__crond();
    my $entries = $cron->get_entries();
    shift @$entries;

    $TIMEVAR = 0;

    my $entry = new Yote::Obj( {
 	enabled => 1,
	repeats => [
	    new Yote::Obj( { repeat_infinite => 1, repeat_interval => 14 } ),
	    new Yote::Obj( { repeat_times => 1, repeat_interval => 3 } ),
	    ],
	scheduled_times => [
	    88,
	    44,
	    99,
	    ],
			       } );
    $cron->add_entry( $entry );

    is( $entry->get_next_time(), 3, "Cron entry 1" );

    my $dolist = $cron->entries();
    is( scalar( @$dolist ), 0, "no cron entries yet ready" );

    $TIMEVAR  = 3;
    $dolist = $cron->entries();
    is( scalar( @$dolist ), 1, "one cron entry now ready" );
    is( $entry->get_next_time(), 3, "next time still 3." );
    $entry->set_enabled( 0 );
    $dolist = $cron->entries();
    is( scalar( @$dolist ), 0, "disabled not ready" );
    $entry->set_enabled( 1 );
    $dolist = $cron->entries();
    is( scalar( @$dolist ), 1, "reenabled now ready" );
    is( scalar( @{ $entry->get_repeats() } ), 2, "two repeat entries" );

    $cron->_mark_done( $entry );
    is( $entry->get_next_time(), 14, "next time is ready" );
    is( scalar( @{ $entry->get_repeats() } ), 1, "one repeat entries" );

    $TIMEVAR  = 11;
    $dolist = $cron->entries();
    is( scalar( @$dolist ), 0, "one cron entry not yet ready" );

    $TIMEVAR  = 14;
    $dolist = $cron->entries();
    is( scalar( @$dolist ), 1, "one cron entry now ready" );
    $cron->_mark_done( $entry );
    is( $entry->get_next_time(), 28, "next time is ready" );

    $TIMEVAR  = 33;
    $dolist = $cron->entries();
    is( scalar( @$dolist ), 1, "one cron entry now ready" );
    $cron->_mark_done( $entry );
    is( $entry->get_next_time(), 42, "next time is ready" );
    $entry->set_enabled( 0 );
    $dolist = $cron->entries();
    is( scalar( @$dolist ), 0, "crons disabled" ); 

    $entry->set_enabled( 1 );
    $TIMEVAR = 88;
    $dolist = $cron->entries();
    is( scalar( @{ $entry->get_scheduled_times() } ), 3, "three scheduled entries" );
    is( scalar( @$dolist ), 1, "one cron entry now ready" );
    $cron->_mark_done( $entry );
    is( $entry->get_next_time(), 99, "next scheduled times" );
    is( scalar( @{ $entry->get_scheduled_times() } ), 1, "one scheduled entries" );

    $TIMEVAR = 98;
    $dolist = $cron->entries();
    is( scalar( @{ $entry->get_scheduled_times() } ), 1, "one scheduled entries" );
    is( scalar( @$dolist ), 0, "no cron entry not yet ready" );
    $cron->_mark_done( $entry );
    is( $entry->get_next_time(), 99, "next scheduled times" );

    $TIMEVAR = 99;
    $dolist = $cron->entries();
    is( scalar( @$dolist ), 1, "one cron entry now ready" );
    $cron->_mark_done( $entry );
    is( scalar( @{ $entry->get_scheduled_times() } ), 0, "no more scheduled entries" );
    is( $entry->get_next_time(), 102, "next scheduled times" );

    $entry->set_repeats([]);
    $dolist = $cron->entries();
    is( scalar( @{ $entry->get_scheduled_times() } ), 0, "three scheduled entries" );
    is( scalar( @$dolist ), 0, "no more cron entries" );
    

    is( scalar( @{ $entry->get_scheduled_times() } ), 0, "no more scheduled entries" );

    # zoot,  toot, realroot, NEWROOT ( master )

    # the following block is copied from above
    $root = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    $root->_update_master_root( "NEWROOT",Yote::ObjProvider::encrypt_pass( "NEWPW", "NEWROOT" ) );
    my $master_root = $root->login( { h => 'NEWROOT', p => 'NEWPW' } )->{l};
    ok( $master_root->is_root(), "Master root is root" );
    my $master_acct = $root->__get_account( $master_root );
    my $zl = $root->login( { h => 'zoot', p => 'naughty' } )->{l};
    $zl->set__is_root( 1 );

    Yote::ObjProvider::stow_all();
    my $toot_notroot = $root->login( { h => 'toot', p => 'toor' } )->{l};
    ok( ! $toot_notroot->is_root(), "Toot notroot is not root" );
    my $toot_notroot_acct = $root->__get_account( $toot_notroot );
    my $zoot_root = $root->login( { h => 'zoot', p => 'naughty' } )->{l};
    ok( $zoot_root, "Zoot is root" );
    my $zoot_root_acct = $root->__get_account( $zoot_root );

    my $cute_login = $root->create_login( { h => 'cute', p => 'naughty', e => "cute\@tooz.com" } )->{l};
    my $cute_notroot_acct = $root->__get_account( $cute_login );

    my $ro = new Yote::RootObj();
    is_deeply( $ro->paginate( { name => "_foo", }, $master_acct ), [], "master root can paginate root obj private container" );
    is_deeply( $ro->paginate( { name => "_foo", }, $zoot_root_acct ), [], "other root can paginate root obj private container" );
    eval { 
	$ro->paginate( { name => "_foo", }, $toot_notroot_acct );
	fail( "nonroot account able to paginate root obj private container" );
    };
    like( $@, qr/^Access Error/,"nonroot account unable to paginate root obj private container" );

    my $uo = new Yote::UserObj( { __creator =>  $toot_notroot_acct } );
    is_deeply( $uo->paginate( { name => "_foo", }, $master_acct ), [], "master root can paginate user obj private container" );
    is_deeply( $uo->paginate( { name => "_foo", }, $zoot_root_acct ), [], "other root can paginate user obj private container" );
    is_deeply( $uo->paginate( { name => "_foo", }, $toot_notroot_acct ), [], "creator can paginate user obj private container" );
    eval { 
	$ro->paginate( { name => "_foo", }, $cute_notroot_acct );
	fail( "nonroot account able to paginate root obj private container" );
    };
    like( $@, qr/^Access Error/,"nonroot nonowner account unable to paginate user obj private container" );
    is_deeply( $uo->paginate( { name => "foo", }, $cute_notroot_acct ), [], "nonroot, noncreator can paginate user obj public container" );
    eval { 
	$ro->hash( { name => "foo", value => 'bar' }, $cute_notroot_acct );
	fail( "nonroot, nocreator account able to insert into into user obj private container" );
    };
    like( $@, qr/^Access Error/,"nonroot nonowner account unable to insert data into  user obj public container" );
} #io_independent_tests

1;

__END__

=head1 NAME

Yote::IO::TestUtil

=head1 DESCRIPTION

This package exists to provide IO engine independent tests for the different stores.

=head1 METHODS

=over 4

=item compare_sets( set1,set2, message )

Compares set1 and set2 

=item fail_permission( obj, acct,cmd, data, msg )

Checks to make sure the command fails for the object and account.

=item io_independent_tests( root_obj )

Runs a suite of tests

=item pass_permission( obj, acct,cmd, data, msg )

Checks to make sure the command passes for the object and account.

=back

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com


=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
