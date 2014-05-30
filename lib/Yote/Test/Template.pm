package Yote::Test::Template;

use strict;
use warnings;

use Yote::Obj;

use parent 'Yote::AppRoot';

use vars qw($VERSION);

$VERSION = '0.02';

sub _init {
    my $self = shift;

    $self->set_sandbox( new Yote::Obj() );
}

sub reset {
    my $self = shift;
    $self->set_sandbox( new Yote::Obj() );
}

1;

__END__

=head1 PUBLIC METHODS

=over 4

=item reset

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
