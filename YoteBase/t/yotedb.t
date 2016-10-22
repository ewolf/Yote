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
test_suite();
done_testing;

exit( 0 );


sub test_suite {

    my $store = Yote::open_store( $dir );
    my $yote_db = $store->{_DATASTORE};
    my $root_node = $store->fetch_root;

    $root_node->add_to_myList( { objy => 
        $store->newobj( { 
            someval => 124.42,
            somename => 'Käse',
            someobj => $store->newobj( {
                innerval => "This is an inner val with Käse essen ",
                                      } ),
                        } ),
                               } );

    is( $root_node->get_myList->[0]{objy}->get_somename, 'Käse', "utf 8 character defore stow" );

    $store->stow_all;

    is( $root_node->get_myList->[0]{objy}->get_somename, 'Käse', "utf 8 character after stow before load" );

    # objects created : root, myList, a hash in myslist, a newobj
    #                   in the hash, a newobj in the obj
    # so 5 things

    my $max_id = $yote_db->_max_id();
    is( $max_id, 5, "Number of things created" );

    my $dup_store = Yote::open_store( $dir );

    my $dup_db = $dup_store->{_DATASTORE};

    $max_id = $dup_db->_max_id();
    is( $max_id, 5, "Number of things created in newly opened store" );

    my $dup_root = $dup_store->fetch_root;

    $max_id = $dup_db->_max_id();
    is( $max_id, 5, "Number of things created in newly opened store" );

    is( $dup_root->{ID}, $root_node->{ID} );
    is_deeply( $dup_root->{DATA}, $root_node->{DATA} );
    is( $dup_root->get_myList->[0]{objy}->get_somename, 'Käse', "utf 8 character saved in yote object" );
        is( $dup_root->get_myList->[0]{objy}->get_someval, '124.42', "number saved in yote object" );   
    is( $dup_root->get_myList->[0]{objy}->get_someobj->get_innerval, 
        "This is an inner val with Käse essen " );
    
    # filesize of $dir/1_OBJSTORE should be 360

    # recycle test. This should eliminate the following :
    # the old myList, the objy, the someobj of objy, so 3 items

    my $list_to_remove = $root_node->get_myList();
    my $hash_in_list = $list_to_remove->[0];

    $root_node->set_myList( [ ] );
    $store->stow_all;

    is( $store->run_recycler, 0, "none 4 deleted things recyled because the top non-weak reference is kept." );

    undef $hash_in_list;

    is( $store->run_recycler, 0, "none 4 deleted things recyled because the top non-weak reference is kept." );

    $hash_in_list = $list_to_remove->[0];

    undef $list_to_remove;

    is( $store->run_recycler, 1, "just list is removed. it is not referenced by other removed items that still have references." );

    undef $hash_in_list;

    is( $store->run_recycler, 3, "all 3 remaining things that can't trace to the root are removed" );

} #test suite


__END__
