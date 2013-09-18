use strict;
use warnings;

my( %calls, %times, %has_sub_parts );
while(<>) {
    if( /^@ (.*) : (.*)/ ) {
	my $time = $2;
	my( $leaf, @stack ) = reverse split(/,/, $1 );
	$calls{ $leaf }++;
	$times{ $leaf } += $time;
	for( my $i=0; $i<@stack; $i++ ) {
	    $has_sub_parts{ $stack[ $i ] } = 1;
	}
    }
}

print join( "\n", map { "$_ : " . int( $times{$_} / $calls{$_} ) . " $times{$_}" } sort { ($times{$a} / $calls{$a}) <=> ($times{$b} / $calls{$b} ) } grep { ! $has_sub_parts{ $_ } } keys %calls ) . "\n";
