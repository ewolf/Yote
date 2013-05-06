package Yote::Util::Blog;

use strict;

use warnings;

use base 'Yote::Obj';

use Yote::Util::BlogPost;
use Yote::Util::Tag;

use vars qw($VERSION);

$VERSION = '0.02';

sub _init {
    my $self = shift;
    
    $self->set_tagger( new Yote::Util::Tag() );

    $self->set_posts( [] );
} #_init

sub _load {
    my $self = shift;
#    $self->get_posts( [] );
}

sub remove_post {
    my( $self, $data, $acct ) = @_;

    die "Need admin to remove" unless $acct && ( $acct->get_login()->is_root() || $acct->_is( $data->get_author() ) );

    $self->remove_from_posts( $data );

}

sub post {
    my( $self, $data, $acct ) = @_;

    my $post = new Yote::Util::BlogPost();
    $post->set_blog( $self );
    $post->set_author( $acct );

    $post->set_content( $data->{ content } );
    $post->set_subject( $data->{ subject } );
    $post->set_created_on( time() );

    $self->add_to_posts( $post );

    return $post;
} #post

sub read {
    my( $self, $data, $acct ) = @_;
}

1;

__END__

post, edit, vote, tag, rate, moderate



=head1 NAME

Yote::Util::Blog

=head1 DESCRIPTION

The blog holds onto blog posts.

=head1 PUBLIC METHODS

=over 4


=back

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
