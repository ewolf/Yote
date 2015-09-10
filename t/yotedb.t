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

    my $dup_store = Yote::open_store( $dir );
    my $dup_root = $dup_store->fetch_root;

    is( $dup_root->{ID}, $root_node->{ID} );
    is_deeply( $dup_root->{DATA}, $root_node->{DATA} );

    is( $dup_root->get_myList->[0]{objy}->get_someobj->get_innerval, 
        "This is an inner val" );

    
} #test suite


__END__
