#!/usr/bin/perl

use strict;
use warnings;

use Yote::Obj;

use Data::Dumper;
use File::Temp qw/ :mktemp tempdir /;
use Test::More;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    use_ok( "Yote::Obj" ) || BAIL_OUT( "Unable to load Yote::Obj" );
}

# -----------------------------------------------------
#               init
# -----------------------------------------------------

my $dir = tempdir( CLEANUP => 1 );

test_suite;
done_testing;

exit( 0 );


sub test_suite {
    Yote::Obj::init( { store => $dir, } );

    



   Yote::ObjProvider::stow_all();
    $recycled = Yote::ObjProvider::recycle_objects();
    is( $recycled, 4, "recycled 4 objects" );

    my $recyc_ids = $Yote::ObjProvider::DATASTORE->get_recycled_ids;
    is( @$recyc_ids, 4, "four recycled ids" );
    for( @$recyc_ids ) {
        ok( $old_ids{ $_ }, "$_ was recycled" );
    }

    Yote::IO::TestUtil::io_independent_tests( $root );
} #test suite


__END__
