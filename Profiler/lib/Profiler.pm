package Profiler;

use strict;
use warnings;

use Aspect;
use Time::HiRes;
use Data::Dumper;

use File::Temp qw/ tempfile /;

our( @stack, %calltimes, %callers, %calls );

#my( $fh, $tmpFile ) = tempfile( "profilerFooXXXXXX", DIR => '/tmp' );
my $tmpFile = '/tmp/foo';

sub analyze {
    #analyze results from the temp file
}

sub init {
    my $re = shift || qr/^main.*/;
    my $tag = shift || 'sub';
    around {
        my $subname = $_->{sub_name};
        my $start = [Time::HiRes::gettimeofday]; # returns [ seconds, microseconds ]

        
        push @stack, $subname;
        $_->proceed;

        pop @stack;

        map { $callers{$subname}{$_}++; $calls{$_}{$subname}++ } @stack;
        
        # tv_interval returns floating point seconds, convert to ms
        push @{$calltimes{$subname}}, 1_000 * Time::HiRes::tv_interval( $start );

        my $line = "$subname|" . (1_000 * Time::HiRes::tv_interval( $start ) ) . "|" . join(",", @stack );
        `echo '$line' >> $tmpFile`;

        if ( @stack == 0 ) {
            # end condition

            # calculate
            my %stats;
            my $longsub = 0;
            for my $sub ( keys %calltimes ) {
                if( length( $sub ) > $longsub ) { $longsub = length( $sub ) };
                my @times = sort { $a <=> $b }  @{$calltimes{$sub}};
                my $calls = scalar( @times );
                my $tottime = 0;
                map { $tottime += $_ } @times;
                $stats{$sub} = {
                    calls => $calls,
                    total => $tottime,
                    mean  => $times[ int( @times/2 ) ],
                    avg   => $calls ? int($tottime / $calls) : '?',
                    max   => $times[$#times],
                    min   => $times[0],
                };
            }
            my( @titles ) = ( 'sub', 'calls', 'total time', 'mean time', 'avg time', 'max time', 'min time' );
            my $minwidth = 10;
            print "\n\'$tag' performance stats ( all times are in ms)\n\n";
            print sprintf( "%*s  | ", $longsub, "sub" ). join( " | ", map { sprintf( "%*s", $minwidth, $_ ) } @titles[1..$#titles] ) ."\n";
            print '-' x $longsub . '--+-' . join( "-+-", map { '-' x $minwidth } @titles[1..$#titles] )."\n";
            for my $sub (sort { $stats{$b}{calls} <=> $stats{$a}{calls} } keys %stats) {
                print join( " | ", sprintf( "%*s ", $longsub, $sub ),
                            map { sprintf( "%*s", $minwidth, $stats{$sub}{$_} ) }
                                qw( calls total mean avg max min ) )."\n";
            }
            print "\n\n";
            if( 0 ) {
            print "Who Calls What\n";
            for my $sub (sort { $stats{$a}->{total} <=> $stats{$b}->{total} } keys %stats) {
                my $calls = [sort { $calls{$sub}{$b} <=> $calls{$sub}{$a} } keys %{$calls{$sub}||{}}];
                my $called_by = [sort { $callers{$sub}{$b} <=> $callers{$sub}{$a} } keys %{$callers{$sub}||{}}];
                print STDERR " $sub\n" .
                    "   Called by :" . ( @$called_by ? "\n\t" . join( "\n\t", map { "$_ $callers{$sub}{$_}" } @$called_by ) : '<not called>' ) . "\n" .
                    "   Calls :" . ( @$calls ? "\n\t" . join( "\n\t", map { "$_ $calls{$sub}{$_}" }  @$calls ) : '<does not make calls>' ) . "\n";
            }
            print "\n\n";
        }
        }

    } call $re;
}

1;

__END__
