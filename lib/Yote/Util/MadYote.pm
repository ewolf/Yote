package Yote::Util::MadYote;

use strict;
use warnings;

use base 'Yote::AppRoot';

use Yote::Util::ChatBoard;
use Yote::Util::Blog;

use vars qw($VERSION);
$VERSION = '0.021';

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

sub suggestion_box {
    my( $self, $text, $acct, $env ) = @_;
    
    $self->add_to__suggestion_box( 
	Yote::Obj->new( {
	    from         => $acct ? $acct->get_login()->get_handle() : $env->{REMOTE_ADDR},
	    is_from_acct => defined( $acct ),
	    message      => $text
			} )
	);

} #suggestion_box

sub remove_suggestion {
    my( $self, $sugg, $acct, $env ) = @_;
    
    if( $acct->get_login()->is_root() ) {
	$self->remove_from__suggestion_box( $sugg );
    }

} #remove_suggestion

1;

__END__

=head1 PUBLIC API METHODS

=over 4

=item update( hashref )

Pass in a hash ref of update fields and values ( now limited to MOTD ).

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
