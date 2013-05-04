package Yote::Util::MadYote;

use strict;
use warnings;

use base 'Yote::AppRoot';

use Yote::Util::ChatBoard;
use Yote::Util::Blog;

sub _init {

    my $self = shift;
    
    my $cb = new Yote::Util::ChatBoard();
    $cb->set_requires_account( 0 );
    
    $self->set_chat_board( $cb );

    $self->set_MOTD( '' );

    $self->set_news_blog( new Yote::Util::Blog() );

} #_init

sub _load {
    my $self = shift;
    $self->get_MOTD( '' );
    $self->get_news_blog( new Yote::Util::Blog() );
}

sub update {
    my( $self, $data, $acct ) = @_;
    
    $self->_update( $data, 'MOTD' );

} #update

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
