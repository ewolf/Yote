use strict;
use warnings;

use Yote;

use Data::Dumper;
use File::Temp qw/ :mktemp tempdir /;
use Test::More;
use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    use_ok( "Yote" ) || BAIL_OUT( "Unable to load 'Yote'" );
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

my $dir = tempdir( CLEANUP => 1 );
#test_suite();
test_arry();
done_testing;

exit( 0 );

sub test_suite {

    my $store = Yote::open_store( $dir );
    my $root_node = $store->fetch_root;

    $root_node->add_to_myList( { objy =>
        $store->newobj( {
            someval => 124.42,
            somename => 'Käse',
            someobj => $store->newobj( {
                binnerval => "`SPANXZ",
                linnerval => "SP`A`NXZ",
                zinnerval => "PANXZ`",
                innerval => "This is an \\ inner `val\\`\n with Käse \\\ essen ",
                                      } ),
                        } ),
                               } );
    my $il = $root_node->get_myList; my $tied = tied(@$il);

    is( $root_node->get_myList->[0]{objy}->get_somename, 'Käse', "utf 8 character defore stow" );

    $store->stow_all;

    is( $root_node->get_myList->[0]{objy}->get_somename, 'Käse', "utf 8 character after stow before load" );

    # objects created : root, myList, array block in mylist, a hash in myslist + its 1 inner list, a newobj
    #                   in the hash, a newobj in the obj
    # so 6 things

    my $dup_store = Yote::open_store( $dir );

    my $dup_root = $dup_store->fetch_root;

    is( $dup_root->[Yote::Obj::ID], $root_node->[Yote::Obj::ID] );
    is_deeply( $dup_root->[Yote::Obj::DATA], $root_node->[Yote::Obj::DATA] );
    is( $dup_root->get_myList->[0]{objy}->get_somename, 'Käse', "utf 8 character saved in yote object" );
    is( $dup_root->get_myList->[0]{objy}->get_someval, '124.42', "number saved in yote object" );

    is( $dup_root->get_myList->[0]{objy}->get_someobj->get_innerval,
        "This is an \\ inner `val\\`\n with Käse \\\ essen " );
    is( $dup_root->get_myList->[0]{objy}->get_someobj->get_binnerval, "`SPANXZ" );
    is( $dup_root->get_myList->[0]{objy}->get_someobj->get_linnerval, "SP`A`NXZ" );
    is( $dup_root->get_myList->[0]{objy}->get_someobj->get_zinnerval, "PANXZ`" );

    # filesize of $dir/1_OBJSTORE should be 360

    # purge test. This should eliminate the following :
    # the old myList, the hash first element of myList, the objy in the hash, the someobj of objy, so 4 items

    my $list_to_remove = $root_node->get_myList();

    $list_to_remove->[9] = "NINE";

    $store->stow_all;

    undef $list_to_remove;
    $list_to_remove = $root_node->get_myList();

    my $hash_in_list = $list_to_remove->[0];

    my $ltied = tied @$list_to_remove;
    my $list_block_id = $ltied->[1][0];
    
    my $list_to_remove_id = $store->_get_id( $list_to_remove );
    my $hash_in_list_id   = $store->_get_id( $hash_in_list );

    my @bucket_in_hash_in_list;
    my $bucket_in_hash_in_list_id   = $store->_get_id( $hash_in_list );

    my $objy              = $hash_in_list->{objy};
    my $objy_id           = $store->_get_id( $objy );
    my $someobj_id        = $store->_get_id( $objy->get_someobj );
    undef $objy;


    $root_node->set_myList( [] );

    $store->stow_all;

    my $quickly_removed_obj = $store->newobj( { soon => 'gone', bigstuff => ('x'x10000) } );
    my $quickly_removed_id = $quickly_removed_obj->[Yote::Obj::ID];
    push @$list_to_remove, "SDLFKJSDFLKJSDFKJSDHFKJSDHFKJSHDFKJSHDF" x 3, $quickly_removed_obj;
    $list_to_remove->[87] = "EIGHTYSEVEN";

    $store->stow_all;



    undef $list_to_remove;
    undef $quickly_removed_obj;


    undef $hash_in_list;

    undef $dup_root;

    undef $root_node;

    ok( ! $store->_fetch( $list_to_remove_id ), "removed list still removed" );
    ok( ! $store->_fetch( $hash_in_list_id ), "removed hash id still removed" );
    ok( ! $store->_fetch( $objy_id ), "removed objy still removed" );
    ok( ! $store->_fetch( $someobj_id ), "removed someobj still removed" );

    $Yote::Hash::SIZE = 7;

    my $thash = $store->fetch_root->get_test_hash({});
    # test for hashes large enough that subhashes are inside

    my( %confirm_hash );
    my( @alpha ) = ("A".."G");
    my $val = 1;
    for my $letter (@alpha) {
        $thash->{$letter} = $val;
        $confirm_hash{$letter} = $val;
        $val++;
    }

    $val = 1;
    for my $letter (@alpha) {
        is( $thash->{$letter}, $val++, "Hash value works" );
    }
    $thash->{A} = 100;
    is( $thash->{A}, 100, "overriding hash value works" );
    delete $thash->{A};
    delete $confirm_hash{A};
    ok( ! exists($thash->{A}), "deleting hash value works" );
    $thash->{G} = "GG";
    $confirm_hash{G} = "GG";

    is_deeply( [sort keys %$thash], ["B".."G"], "hash keys works for the simpler hashes" );

    # now stuff enough there so that the hashes must overflow
    ( @alpha ) = ("AA".."ZZ");
    for my $letter (@alpha) {
        $thash->{$letter} = $val;
        $confirm_hash{$letter} = $val;
        $val++;
    }
    $store->stow_all;

    my $sup_store = Yote::open_store( $dir );
    $thash = $sup_store->fetch_root->get_test_hash;
    is_deeply( [sort keys %$thash], [sort ("B".."G","AA".."ZZ")], "hash keys works for the heftier hashes" );

    is_deeply( $thash, \%confirm_hash, "hash checks out keys and values" );

    # array tests
    # listy test because
    $Yote::Array::MAX_BLOCKS  = 4;
    
     $root_node = $store->fetch_root;
    my $l = $root_node->get_listy( [] );

    push @$l, "ONE", "TWO";
    is_deeply( $l, ["ONE", "TWO"], "first push" );
    is( @$l, 2, "Size two" );
    is( $#$l, 1, "last index 1" );

    push @$l, "THREE", "FOUR", "FIVE";
    is_deeply( $l, ["ONE", "TWO", "THREE", "FOUR", "FIVE"], "push 1" );
    is( @$l, 5, "Size five" );
    is( $#$l, 4, "last index 1" );
    print STDERR Data::Dumper->Dump([$l,"WIS"]);

    push @$l, "SIX", "SEVEN", "EIGHT", "NINE";

    is_deeply( $l, ["ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE"], "push 2" );
    is( @$l, 9, "Size nine" );

    push @$l, "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN";
    is_deeply( $l, ["ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN"], "push 3" );
    is( @$l, 16, "Size sixteen" );

    push @$l, "SEVENTEEN", "EIGHTTEEN";
    is_deeply( $l, ["ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTTEEN"], "push 4" );
    is( @$l, 18, "Size eighteen" );
    is_deeply( ["SIXTEEN","SEVENTEEN","EIGHTTEEN",undef],[@$l[15..18]], "nice is slice" );

    push @$l, "NINETEEN";
    is_deeply( $l, ["ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTTEEN", "NINETEEN"], "push 5" );
    is( @$l, 19, "Size nineteen" );
    is_deeply( ["SIXTEEN","SEVENTEEN","EIGHTTEEN","NINETEEN"],[@$l[15..18]], "nice is slice" );

    push @$l, "TWENTY","TWENTYONE";
    is_deeply( $l, ["ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTTEEN", "NINETEEN", "TWENTY","TWENTYONE"], "push 6" );
    is( @$l, 21, "Size twentyone" );
    print STDERR Data::Dumper->Dump([$l,"TINKER"]);
    my $v = shift @$l;
    is( $v, "ONE" );
    print STDERR Data::Dumper->Dump([$l,"SOW"]);
    is_deeply( $l, ["TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTTEEN", "NINETEEN", "TWENTY","TWENTYONE"], "first shift" );
    is( @$l, 20, "Size twenty" );
    print STDERR Data::Dumper->Dump([$l,"ELLE"]);
    push @$l, $v;
    is_deeply( $l, ["TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTTEEN", "NINETEEN", "TWENTY","TWENTYONE", "ONE"], "push 7" );
    is( @$l, 21, "Size twentyone again" );
    print STDERR Data::Dumper->Dump([$l,"BLSO"]);
    unshift @$l, 'ZERO';

    is_deeply( $l, ["ZERO", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTTEEN", "NINETEEN", "TWENTY","TWENTYONE", "ONE"], "first unshift" );
    is( @$l, 22, "Size twentytwo again" );

    # test push, unshift, fetch, fetchsize, store, storesize, delete, exists, clear, pop, shift, splice

    my $pop = pop @$l;
    is( $pop, "ONE", "FIRST POP" );
    is( @$l, 21, "Size after pop" );

    is( $l->[2], "THREE", "fetch early" );
    is( $l->[10], "ELEVEN", "fetch middle" );
    is( $l->[20], "TWENTYONE", "fetch end" );



    my @spliced = splice @$l, 3, 5, "NEENER", "BOINK", "NEENER";

    is_deeply( \@spliced, ["FOUR","FIVE","SIX","SEVEN","EIGHT"], "splice return val" );
    is_deeply( $l, ["ZERO", "TWO", "THREE", "NEENER", "BOINK", "NEENER",
                    "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTTEEN", "NINETEEN", "TWENTY","TWENTYONE"], "first splice" );

    $l->[1] = "TWONE";
    is( $l->[1], "TWONE", "STORE" );

    delete $l->[1];

    is_deeply( $l, ["ZERO", undef, "THREE", "NEENER", "BOINK", "NEENER",
                    "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTTEEN", "NINETEEN", "TWENTY","TWENTYONE"], "first delete" );
    ok( exists( $l->[0] ), "exists" );
    ok( !exists( $l->[1] ), "doesnt exist" );
    ok( !exists( $l->[$#$l+1] ), "doesnt exist beyond" );
    ok( exists( $l->[$#$l] ), "exists at end" );

    my $last = pop @$l;
    is( $last, "TWENTYONE", 'POP' );
    is_deeply( $l, ["ZERO", undef, "THREE", "NEENER", "BOINK", "NEENER",
                    "NINE", "TEN", "ELEVEN", "TWELVE", "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTTEEN", "NINETEEN", "TWENTY"], "more pop" );
    is( scalar(@$l), 18, "pop size" );
    is( $#$l, 17, "pop end" );

    @{$l} = ();
    is( $#$l, -1, "last after clear" );
    is( scalar(@$l), 0, "size after clear" );
    if(0){
    push @$l, 0..10000;
    $store->stow_all;
    my $other_store = Yote::open_store( $dir );
    $root_node = $store->fetch_root;
    my $ol = $root_node->get_listy( [] );

    is_deeply( $l, $ol, "lists compare" );
    }
} #test suite

sub test_arry {
    my $store = Yote::open_store( $dir );
    my $root_node = $store->fetch_root;
    for my $SZ (2..9) {
#    for my $SZ (3..3) {
        $Yote::Array::MAX_BLOCKS  = $SZ;
        my $arry = $root_node->set_arry( [ 1 .. 19 ] );
        my $tied = tied (@$arry);
        my $match = [ 1 .. 19 ];
        is_deeply( $arry, $match, "INITIAL $SZ" );
        is( @$arry, 19, "19 items" );
        is( $#$arry, 18, "last idx is 18" );

        my $a = shift @$arry;
        my $m = shift @$match;
        is( $a, $m, "SHIFT $SZ" );

        is_deeply( $arry, $match, "AFTER SHIFT $SZ" );
        is( @$arry, 18, "18 items" );
        is( $#$arry, 17, "last idx is 17" );
        
        $a = pop @$arry;
        $m = pop @$match;
        is( $a, $m, "POP $SZ" );
        is_deeply( $arry, $match, "AFTER POP $SZ" );
        is( @$arry, 17, "17 items" );
        is( $#$arry, 16, "last idx is 16" );

        my( @a ) = splice @$arry, 3, 4, ("A".."N");
        my( @m ) = splice @$match, 3, 4, ("A".."N");

        is_deeply( $arry, $match, "AFTER SPLICE $SZ" );
        is_deeply( \@a, \@m, "SPLICE return $SZ" );
    }
}

__END__

perl -e '@l = (1,2,3); $l[1] = "A"; print join(",",@l)."\n"'
1,A,3
wolf@talisman:~/proj/Yote/YoteBase$ perl -e '@l = (1,2,3); $l[1] = "A"; print scalar(@l)."\n"'
3
wolf@talisman:~/proj/Yote/YoteBase$ perl -e '@l = (1,2,3); $l[10] = "A"; print scalar(@l)."\n"'
3
wolf@talisman:~/proj/Yote/YoteBase$ perl -e '@l = (1,2,3); $l[10] = "A"; print scalar(@l)."\n"'
11
wolf@talisman:~/proj/Yote/YoteBase$ perl -e '@l = (1,2,3); $l[10] = undef; print scalar(@l)."\n"'perl -e '@l = (1,2,3); $l[10] = undef; print scalar(@l)."\n"'
11
wolf@talisman:~/proj/Yote/YoteBase$ perl -e '@l = (1,2,3); $l[10] = undef; delete $l[10]; print scalar(@l)."\n"'
3
wolf@talisman:~/proj/Yote/YoteBase$ perl -e '@l = (1,2,3); $l[10] = undef; $l[9] = undef; delete $l[10]; print scalar(@l)."\n"'
10
wolf@talisman:~/proj/Yote/YoteBase$ perl -e '@l = (1,2,3); $l[10] = undef; $l[9] = undef; delete $l[10]; print scalar(@l)."\n"'
