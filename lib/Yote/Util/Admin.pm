package Yote::Util::Admin;

# app for admin control

use strict;

use warnings;
no warnings 'uninitialized';

use vars qw($VERSION);

use base 'Yote::AppRoot';

$VERSION = '0.01';

use Yote::Util::CMS;

sub _init {
    my $self = shift;
    $self->set_cms( new Yote::Util::CMS() );
} #_init

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
