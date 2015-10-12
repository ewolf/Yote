package Devel::SimpleProfiler;

use strict;
use warnings;

use Aspect;
use Time::HiRes;
use Data::Dumper;

use File::Temp qw/ tempfile /;

our( @stack, %calltimes, %callers, %calls, $tmpFile, $re );

=head1 NAME

   Devel::SimpleProfiler - quick and dirty perl code profiler

=head1 SYNPOSIS

 use Devel::SimpleProfiler;
 Devel::SimpleProfiler::init( "/tmp/tmpfile",
                 qr/RegexToMatchSubNames/ );
 Devel::SimpleProfiler::start;

 ....

 if( ! fork ) {
     # must restart for child process
     Devel::SimpleProfiler::start;
 }

 ....

 Devel::SimpleProfiler::analyze;
 exit;

 # ---- PRINTS OUT -----
 performance stats ( all times are in ms)

             sub  | # calls | total t | mean t | avg t | max t | min t
 -----------------+---------+---------+--------+-------+-------+------
 main::test_suite |       1 |    2922 |   2922 |  2922 |  2922 |  2922
     SomeObj::new |       3 |      26 |      8 |     8 |     8 |     8
  OtherThing::fun |      27 |     152 |      1 |     5 |    63 |     0

 .... 

=head1 DESCRIPTION

    This is meant to be a simple way to get a performance benchmark for perl subs.
    It uses the fantastic Aspect module written by Adam Kennedy, Marcel Gruenauer 
    and Ran Eilam to monkey patch select perl subs and gather statistics about them.

=head1 METHODS

=head2 init

    init takes two arguments : a temp file to use and a regular expression to find
    subs to measure. By default, the file is /tmp/foo and the regex is qr/^main:/;
 
    init should be called once for a run.

=cut
sub init {
    ( $tmpFile, $re ) = @_;
    $tmpFile ||= '/tmp/foo';
    $re      ||= qr/^main:/;
    unlink $tmpFile;
}

=head2 analyze

    analyze simply outputs the data collected from the profiler so far in a table with
    the columns
      * sub name
      * total number of calls
      * total time in ms
      * mean time in ms
      * average time in ms
      * max time in ms
      * min time in ms

    This can be called as many times as desired.

=cut
sub analyze {
    my( %funtimes, %funcalls, %funcalled );
    open( IN, "<$tmpFile" );
    while( <IN> ) {
        chomp;
        my( $fun, $time, $stack ) = split /\|/, $_;
        push @{$funtimes{ $fun }}, $time;
        my( @stack ) = split ',', $stack;
        for my $call ( @stack ) {
            $funcalls{$call}{$fun}++;
            $funcalled{$fun}{$call}++
        }
    }
    _analyze( \%funtimes, \%funcalled, \%funcalls );
} #analyze

sub _analyze {
    my( $calltimes, $callers, $calls ) = @_;
    my %stats;
    my $longsub = 0;
    for my $subr ( keys %$calltimes ) {
        if( length( $subr ) > $longsub ) { $longsub = length( $subr ) };
        my @times = sort { $a <=> $b }  @{$calltimes->{$subr}};
        my $calls = scalar( @times );
        my $tottime = 0;
        map { $tottime += $_ } @times;
        $stats{$subr} = {
            calls => $calls,
            total => $tottime,
            mean  => $times[ int( @times/2 ) ],
            avg   => $calls ? int($tottime / $calls) : '?',
            max   => $times[$#times],
            min   => $times[0],
        };
    }
    my( @titles ) = ( 'sub', '# calls', 'total t', 'mean t', 'avg t', 'max t', 'min t' );
    my $minwidth = 7;
    print "\n performance stats ( all times are in ms)\n\n";
    print sprintf( "%*s  | ", $longsub, "sub" ). join( " | ", map { sprintf( "%*s", $minwidth, $_ ) } @titles[1..$#titles] ) ."\n";
    print '-' x $longsub . '--+-' . join( "-+-", map { '-' x $minwidth } @titles[1..$#titles] )."\n";
#    for my $subr (sort { $stats{$b}{total} <=> $stats{$a}{total} } keys %stats) {
    for my $subr (sort { $stats{$b}{avg} <=> $stats{$a}{avg} } keys %stats) {
        print join( " | ", sprintf( "%*s ", $longsub, $subr ),
                    map { sprintf( "%*d", $minwidth, $stats{$subr}{$_} ) }
                    qw( calls total mean avg max min ) )."\n";
    }
    print "\n\n";
    if( 0 ) {
        print "Who Calls What\n";
        for my $subr (sort { $stats{$a}->{total} <=> $stats{$b}->{total} } keys %stats) {
            my $calls = [sort { $calls->{$subr}{$b} <=> $calls->{$subr}{$a} } keys %{$calls->{$subr}||{}}];
            my $called_by = [sort { $callers->{$subr}{$b} <=> $callers->{$subr}{$a} } keys %{$callers->{$subr}||{}}];
            print " $subr\n" .
                "   Called by :" . ( @$called_by ? "\n\t" . join( "\n\t", map { "$_ $callers->{$subr}{$_}" } @$called_by ) : '<not called>' ) . "\n" .
                "   Calls :" . ( @$calls ? "\n\t" . join( "\n\t", map { "$_ $calls->{$subr}{$_}" }  @$calls ) : '<does not make calls>' ) . "\n";
        }
        print "\n\n";
    }
} #_analyze 

=head2 start

    This is called to start or continue the data collection process. It takes an option
    regex parameter in case something different is desired 

=cut
sub start {
    my $re = shift || $re;
    my $count = 0;
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
        ++$count;
        open( OUT, ">>$tmpFile" );
        print OUT "$line\n";
        close OUT;

    } call $re;
} #start

1;

__END__
