package Yote::DummyCache;

use strict;
use warnings;
no warnings 'uninitialized';

use vars qw($VERSION);

$VERSION = '0.01';

sub new {
    my( $pkg ) = @_;
    my $class = ref( $pkg ) || $pkg;
    return bless {}, $class;
} #new

sub flush {
} #flush

sub fetch {
} #fetch

sub stow {
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
