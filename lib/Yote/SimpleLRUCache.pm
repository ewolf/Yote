package Yote::SimpleLRUCache;

sub new {
    my( $pkg, $size, $boxes ) = @_;
    my $class = ref( $pkg ) || $pkg;
    $size ||= 50;
    $boxes || 5;
    my $self = {
	size  => $size,
	boxes => [map { {} } (1..$boxes)]
    };
    return bless $self, $class;
} #new

sub fetch {
    my( $self, $id ) = @_;
    for my $box (@{$self->{ boxes }}) {
	my $val = $box->{ $id };
	$self->{hits}++;
	return $val if defined( $val );
    }
    $self->{misses}++;
    return undef;
} #fetch

sub stow {
    my( $self, $id, $val ) = @_;
    if( scalar( keys %{ $self->{ boxes }[0] } ) > $self->{ size } ) {
	pop @{ $self->{ boxes } };
	unshift @{ $self->{ boxes } }, {};
	print STDERR "POPPING BOX\n";
    }
    $self->{ boxes }[ 0 ]{ $id } = $val;
} #stow

1;

__END__
