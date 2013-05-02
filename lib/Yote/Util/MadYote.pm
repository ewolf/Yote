package Yote::Util::MadYote;

use strict;
use warnings;

use base 'Yote::AppRoot';

use Yote::Util::ChatBoard;

sub _init {

    my $self = shift;
    
    my $cb = new Yote::Util::ChatBoard();
    $cb->set_requires_account( 0 );
    
    $self->set_chat_board( $cb );

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
