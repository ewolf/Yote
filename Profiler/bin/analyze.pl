
use strict;
use warnings;

open( IN, "</tmp/foo" );

my( %funtimes, %funcalls, %funcalled );
while( <IN> ) {
    chomp;
    my( $fun, $time, $stack ) = split '|', $_;
    push @{$funtimes{ $fun }}, $time;
    my( @stack ) = split ',', $stack;
    for my $call ( @stack ) {
        $funcalls{$call}{$fun}++;
        $funcalled{$fun}{$call}++
    }
}
