use strict;
use warnings;

use Yote;

use Data::Dumper;
use File::Temp qw/ :mktemp tempdir /;
use Test::More;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    use_ok( "Yote" ) || BAIL_OUT( "Unable to load Yote::Obj" );
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
            someobj => $store->newobj( {
                innerval => "This is an inner val",
                                      } ),
                        } ),
                               } );

    $store->stow_all;

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

    is( $dup_root->get_myList->[0]{objy}->get_someobj->get_innerval, 
        "This is an inner val" );
    
    # filesize of $dir/1_OBJSTORE should be 360

    # recycle test. This should eliminate the following :
    # the old myList, the objy, the someobj of objy, so 3 items

    my $will_be_gone_but_not_yet = $root_node->get_myList();
    $root_node->set_myList( [ ] );
    $store->stow_all;
    is( $store->run_recycler, 3, "3 of the 4 deleted things recyled. The last one is not recycled because there is still a reference to it even if there is no path to root." );

    undef $will_be_gone_but_not_yet;
    is( $store->run_recycler, 1, "the reference of the above test is removed, so its object should be recycled." );

} #test suite


__END__
