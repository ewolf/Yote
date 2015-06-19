#!/usr/bin/perl

use strict;
use warnings;

use Yote::Cache;

use Data::Dumper;
use Test::More;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

my $purged = "FALSE";

$Yote::Cache::MAX_ITEMS = 10;
my $cache = new Yote::Cache( { CACHE => {
    buckets => 3, 
    on_size_purge => sub {
        $purged = "TRUE";
    },   
                               } } );
is_deeply( $Yote::Cache::B1, { } );
is_deeply( $cache->{buckets}, [ {}, {}, {} ] );
for( 1..10 ) {
    $cache->stow( $_, "foo $_" );
}
is_deeply( $Yote::Cache::B1, { map { $_ => "foo $_" } (1..10) } );
is_deeply( $cache->{buckets}, [ {}, {}, {} ] );

$cache->stow( 11, "foo 11" );
is( $purged, "TRUE" );

is_deeply( $Yote::Cache::B1, { 11 => "foo 11" } );
is_deeply( $cache->{buckets}, [ {map { $_ => "foo $_" } (1..10) }, {}, {} ] );


$cache->purge;
is_deeply( $cache->{buckets}, [ {}, {}, {} ] );

done_testing();

exit;

__END__
