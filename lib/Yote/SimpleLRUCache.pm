package Yote::SimpleLRUCache;

use strict;
use warnings;
no warnings 'uninitialized';

use vars qw($VERSION);

$VERSION = '0.02';

sub new {
    my( $pkg, $size, $boxes ) = @_;
    my $class = ref( $pkg ) || $pkg;
    $size  ||= 500;
    $boxes ||= 50;
    my $self = {
	size  => $size,
	boxes => [map { {} } (1..$boxes)]
    };
    return bless $self, $class;
} #new

sub flush {
    my( $self, $id ) = @_;
    for my $box (@{$self->{ boxes }}) {
	delete $box->{ $id };
    }    
} #flush

sub fetch {
    my( $self, $id ) = @_;
    for my $box (@{$self->{ boxes }}) {
	my $val = $box->{ $id };
	$self->{hits}++;
	return $val if defined( $val );
    }
    $self->{misses}++;
    return;
} #fetch

sub stow {
    my( $self, $id, $val ) = @_;
    if( scalar( keys %{ $self->{ boxes }[0] } ) > $self->{ size } ) {
	pop @{ $self->{ boxes } };
	unshift @{ $self->{ boxes } }, {};
    }
    $self->{ boxes }[ 0 ]{ $id } = $val;
} #stow

1;

__END__

=head1 INIT METHODS

=over 4

=item flush( id )

Removes any object with the given ID from the cache

=item fetch( id )

Return the object by id if it is cached

=item stow( id, obj )

Store the object with the given id

=item new

Create new cache

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
