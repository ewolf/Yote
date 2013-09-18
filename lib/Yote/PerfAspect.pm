package Yote::PerfAspect;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';

use Aspect;

use Time::HiRes;

my @stack;
around {
#    print STDERR Data::Dumper->Dump([$_]);
    print STDERR "Start with $_->{sub_name}\n";
    my $start = [Time::HiRes::gettimeofday];
    push @stack, $_->{sub_name};
    $_->proceed;
    my $time = 1_000_000 * Time::HiRes::tv_interval( $start );
    print STDERR "@ ".join(',',@stack). " : $time\n";
    pop @stack;
} call qr/^Yote:.*[^a-zA-Z_][a-z_].*/;

1;

__END__

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
