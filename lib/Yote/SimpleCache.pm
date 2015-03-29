package Yote::SimpleCache;

use strict;
use warnings;

sub new {
    my( $pkg, $size ) = @_;
    my $class = ref( $pkg ) || $pkg;
    $size ||= 1000;
    return bless { 
        size  => $size,
        third_size => int( $size / 3 ),
        cache => {}, 
        short_cache => [], 
    }, $class;
}

sub empty {
    my $self = shift;
    $self->{cache} = {};
    $self->{short_cache} = [];
}

sub has_key {
    my( $self, $key ) = @_;
    return defined $self->{cache}{$key};
}

sub fetch {
    my( $self, $key ) = @_;
    return $self->{cache}{$key};
} #fetch

sub put {
    my( $self, $key, $val ) = @_;

    my $c = $self->{cache};
    my $sc = $self->{short_cache};

    if( scalar( keys %{$self->{cache}} ) > $self->{size} ){
        my $newc = { map { $_ => $self->{cache}{$_} } map { $sc->[$_] } (0..$self->{third_size}) };
        $self->{cache} = $newc;
    }
    $c->{$key} = $val;
    unshift @$sc, $key;
    pop @$sc if @$sc
} #put


1;

__END__

