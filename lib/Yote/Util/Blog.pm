package Yote::Util::Blog;

use base 'Yote::Obj';

use Yote::Util::Tag;

sub _init {
    my $self = shift;
    
    $self->set_tagger( new Yote::Util::Tag() );

    $self->set_posts( [] );
} #_init

sub _load {
    my $self = shift;
    $self->get_posts( [] );
}

sub post {
    my( $self, $data, $acct ) = @_;

    my $post = new BlogPost();
    $post->set_blog( $self );
    $post->set_author( $acct );

    $post->set_content( $data->{ content } );
    $post->set_subject( $data->{ subject } );
    $post->set_created_on( time() );

    $self->add_to_posts( $post );

} #post

sub read {
    my( $self, $data, $acct ) = @_;
}


package BlogPost;

use base 'Yote::Obj';

# main fields : subject, content, author, blog, created_on, last_edited_on
# can have the following fields : pending, flagged_for_abuse, 

sub update {
    my( $self, $data, $acct ) = @_;

    die "No post given" unless $post;
    die "Must be logged in" unless $acct;
    die "Not author of post" unless $acct->_is( post->get_author() ) || $acct->is_root();

    my $dirty = $self->_update( $data,  qw( subject content ) );
    if( $dirty ) {
	$self->set_last_edited_on( time() );
    }

} #edit_post

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
