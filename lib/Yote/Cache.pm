package Yote::Cache;

use strict;

our $MAX_ITEMS = 10_000_000;
our $B1 = {};

sub new {
    my( $pkg, $opts ) = @_;
    my $buckets = $opts->{CACHE}{buckets} || 2;
    bless {
        buckets    => [map { {} } (1..$buckets)],
        options    => $opts->{CACHE}||{},
    }, $pkg;
} #new

sub fetch {
    my( $self, $key ) = @_;
    my $res = $B1->{$key};
    unless( defined $res ) {
        for my $buck (@{$self->{buckets}}) {
            $res = $buck->{$key};
            if( defined $res ) {
                $B1->{ $key } = $res;
                last;
            }
        }
    }
    $res;
} #fetch

sub stow {
    my( $self, $key, $value ) = @_;
    
    if( scalar( keys( %$B1 ) ) >= $MAX_ITEMS ) {
        # bucket one is filled up, so promote bucket two to
        # its place and create an other bucket two
        my $buckets = $self->{buckets};
        unshift @$buckets, $B1;
        pop @$buckets;
        $B1 = {};
        # hmm, listeners here that listen for the cache bump?
        my $listener = $self->{ options }{ on_size_purge };
        $listener && &{$listener}();
    }

    $B1->{ $key } = $value;
    $value;
} #stow

sub purge {
    my $self = shift;
    my $buckets = $self->{options}{buckets} || 2;
    $B1 = {};
    $self->{buckets} = [map { {} } (1..$buckets)];
    return;
}

1;

__END__
