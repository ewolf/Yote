package Yote::Util::Tag;
use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';

#
# The tagging represents a namespace of tags to items.
#
#  Use
#    my $tagger = new Yote::Util::Tag();
#    $tagger->_add_tag( 'foo', $obj1, $obj2, $obj3 );
#

use base 'Yote::Obj';

sub _init {
    my $self = shift;
    $self->set_tag_to_items( {} );
    $self->set_item_to_tags( {} );
} #_init

#
# Returns list of items that have that tag.
#
sub _items_for_tag {
    my( $self, $tag, $paginate_start, $paginate_length ) = @_;
    my $xpath = $self->_path_to_root() . '/tag_to_items';
    return Yote::ObjProvider::paginate_xpath( $xpath, $paginate_start, $paginate_length );    
} #_items_for_tag


#
# Returns list of items best associated with the tags.
#
sub _items_for_tags {

    my( $self, $args ) = @_;

    my $tags = $args->{tags};
    my $exclude = $args->{exclude_tags};

    my( %res, %scores );

    for my $tag (@$tags) {
	my $items = $self->_items_for_tag( $tag );
	for my $item ( @$items ) {
	    if( $exclude ) {
		next if grep { $self->_has_tag( $item, $_ ) } @$exclude;
	    } #if exclude
	    $res{$item} = $item;
	    $scores{$item}++;
	} #each item
    } #each tag

    return [sort { $scores{$b} <=> $scores{$a} } values %res];

} #_items_for_tags

sub _has_tag {
    my( $self, $item, $tag ) = @_;

    my $xpath = $self->_path_to_root();
    return Yote::ObjProvider::xpath_count( "$xpath/item_to_tags/$tag" ) > 0;
} #_has_tag

#
# Ads the tag to the items in the list.
#
sub _add_tag {
    my( $self, $tag, @items ) = @_;
    my $xpath = $self->_path_to_root();
    for my $item (@items) {
	Yote::ObjProvider::xpath_insert( "$xpath/tag_to_items/$tag", $item );
	Yote::ObjProvider::xpath_insert( "$xpath/item_to_tags/$item->{ID}", $tag );
    }
} #_add_tag

#
# Removes the tag to the items in the list.
#
sub _remove_tag {
    my( $self, $tag, @items ) = @_;
    for my $item (@items) {
	Yote::ObjProvider::xpath_insert( "$xpath/item_to_tags/$item->{ID}/$tag" );
    }
} #_remove_tag

1;

__END__

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
