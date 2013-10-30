package Yote::Util::Counter;

use strict;
use warnings;

use base 'Yote::AppRoot';

sub increment {
    my( $self, $page_name ) = @_;
    my $count = $self->_hash_fetch( 'counts', $page_name ) + 1;
    $self->_hash_insert( 'counts', $page_name, $count );
    return $count;
}

1;

__END__


=head1 NAME

Yote::Util::Counter

=head1 SYNOPSIS

=head1 Yote METHODS

=over 4

=item increment( page name )

Increments the page count of the given page name, then returns the count.

=back

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
