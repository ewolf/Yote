package Yote::Util::ChatBoard;

use strict;
use warnings;

use base 'Yote::AppRoot';

use vars qw($VERSION);

$VERSION = '0.01';

sub _init {
    my $self = shift;
    $self->set_posts( [] );
    $self->set_size( 50 );
    $self->set_requires_account( 1 );
}

sub post {
    my( $self, $data, $acct ) = @_;

    die "Need to be logged in to post" unless $acct || $self->get_requires_account() == 0;
    
    my $posts = $self->get_posts();

    my $name = $acct ? $acct->get_handle() : $data->[ 1 ];
    my $post = $acct ? $data : $data->[ 0 ];

    unshift @$posts, [ $name, $post, time() ];

    pop @$posts if @$posts > $self->get_size();
    
} #post

sub remove_post {
    my( $self, $data, $acct ) = @_;
    
    die "Need admin to remove" unless $acct && $acct->get_login()->is_root();

    $self->remove_from_posts( $data );

} #remove_post

sub sync_all {
    my $self = shift;
    return [ $self->get_posts(), map { @$_ } @{$self->get_posts()} ];
}

1;

__END__

=head1 NAME 

Yote::Util::ChatBoard

=head1 DESCRIPTION

The ChatBoard is a very simple queue for posts. It can be configured to require login.

=head1 AUTHOR

Eric Wolf

=head1 PUBLIC API METHODS

=over 4

=item post( message_or_list )

Post a message to the board. If a user is logged in, the argument is a string message. If not, the message is a list reference where the first argument is the message and the second the name of the poster. The message board does not allow anonymous posting by default. This is controlled by the requires_account switch.

=item remove_post( post )

Removes the given post from this Chat Board. Must be admin or owner to do so.

=item sync_all

Sends all the messages in this chat board to the client at once.



=back




=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
