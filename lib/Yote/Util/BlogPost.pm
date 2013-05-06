package Yote::Util::BlogPost;

use strict;
use warnings;

use base 'Yote::Obj';

use vars qw($VERSION);

$VERSION = '0.02';

# main fields : subject, content, author, blog, created_on, last_edited_on
# can have the following fields : pending, flagged_for_abuse, 

sub update {
    my( $self, $data, $acct ) = @_;

    die "No post given" unless $data;
    die "Must be logged in" unless $acct;
    die "Not author of post" unless $acct->_is( $self->get_author() ) || $acct->is_root();

    my $dirty = $self->_update( $data,  qw( subject content ) );
    if( $dirty ) {
	$self->set_last_edited_on( time() );
    }

} #edit_post

1;

__END__

post, edit, vote, tag, rate, moderate



=head1 NAME

Yote::Util::BlogPost

=head1 DESCRIPTION

A single post for the blog

=head1 PUBLIC METHODS

=over 4

=item update( hashref )

Pass in a hash ref of update fields and values ( now limited to subject and content ).

=back

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
