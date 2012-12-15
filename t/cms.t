#!env perl

use strict;

use Yote::Util::CMS;


use Data::Dumper;
use File::Temp qw/ :mktemp /;
use File::Spec::Functions qw( catdir updir );
use Test::More;
use Test::Pod;
use Time::Piece;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

# -----------------------------------------------------
#               init
# -----------------------------------------------------

my( $fh, $name ) = mkstemp( "/tmp/SQLiteTest.XXXX" );
$fh->close();
Yote::ObjProvider::init(
    datastore      => 'Yote::SQLiteIO',
    sqlitefile     => $name,
    );
test_suite();

done_testing();

unlink( $name );

sub test_suite {
    
    my $cms = new Yote::Util::CMS();

    my $root_node = $cms->fetch_content_node( { path =>  "" } );

    is( $root_node->get_content(), undef, "no content from the start" );
    is( $root_node, $cms, "root node is the initial cms" );

    my $no_node = $cms->fetch_content_node( { path =>  "foo" } );
    is( $no_node, $root_node, "root node returned when path has not been set up" );

    my $node = $cms->fetch_specific_content_node( { path =>  "" } );
    is( $node->get_content(), undef, "no specific content from the start" );

    $cms->attach_content( { content => "This is CMS"} );
    is( $cms->get_content(), "This is CMS", "content attached to root node" );
    is( $no_node->get_content(), "This is CMS", "content attached to root node" );
    is( $root_node->get_content(), "This is CMS", "content attached to root node" );

    $cms->attach_content( { path => "", lang => 'german', content => "Heir ist CMS"} );
    my $lang_node = $cms->fetch_content_node( { lang => 'german' } );
    ok( ! $lang_node->_is( $root_node ), "lang node different than root node" );
    is( $root_node->get_content(), "This is CMS", "content attached to root node" );
    is( $lang_node->get_content(), "Heir ist CMS", "content attached to lang node" );

    my $no_node = $cms->fetch_content_node( { path =>  "foo", lang => 'german' } );
    is( $no_node->get_content(), "Heir ist CMS", "content attached to lang node without path" );

    # test language and region interactions, as well as specific_content_node

    my $na_node   = $cms->attach_content( { path => "foo", region => 'north america', content => "My Foo in North America"} );
    my $na_g_node = $cms->attach_content( { path => "foo", lang => 'german', region => 'north america', content => "Mein Foo vom Nord"} );
    my $na_g_node = $cms->attach_content( { path => "foo", lang => 'german', content => "Mein Foo"} );
    my $g_node   = $cms->fetch_content_node( { path => "foo", lang => 'german', region => 'Rhein' } );
    is( $g_node->get_content(), "Mein Foo", "got a german things" );
    my $fr_node   = $cms->fetch_specific_content_node( { path => "foo", region => 'north america', lang => 'french', content => "My Foo in North America"} );
    is( $fr_node, undef, "specific french node not found" );
    my $close_node = $cms->fetch_content_node( { path => "foo", region => 'north america', lang => 'french', content => "My Foo in North America"} );
    is( $close_node, $na_node, "but general node found for french request" );
    is( $na_node->get_content(), "My Foo in North America", "Requested french but defaulted to english" );
    
    # test dates
    my( $d_start, $d_end, $d_test_between, $d_test_early, $d_test_late ) = qw/ 2012-12-13:02:10 2012-12-13:02:20 2012-12-13:02:15 2012-12-13:01:12 2012-12-13:04:12 /;
    my $na_node   = $cms->attach_content( { path => "foo", region => 'north america', starts => $d_start, ends => $d_end, content => "My Zoo in North America"} );
    my $d_fetch   = $cms->fetch_content_node( { path => "foo", region => 'north america', starts => $d_test_between } );
    is( $d_fetch->get_content(), 'My Zoo in North America', "date specific test match" );
    $d_fetch   = $cms->fetch_content_node( { path => "foo", region => 'north america', starts => $d_test_early } );
    is( $d_fetch->get_content(), 'My Foo in North America', "date specific test early" );
    $d_fetch   = $cms->fetch_content_node( { path => "foo", region => 'north america', starts => $d_test_late } );
    is( $d_fetch->get_content(), 'My Foo in North America', "date specific test late" );

} #test_suite
