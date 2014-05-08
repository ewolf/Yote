package Yote::Util::Pages;

########################################################################
# Pages is a utility for editing and versioning the pages on the site. #
# Author : Eric Wolf						       #
########################################################################

use strict;
use warnings;

use parent 'Yote::AppRoot';

use Yote::RootObj;


sub _init {
    my $self = shift;
    $self->set__pages({});
}

sub reload_from_file {
    my( $self, $url, $acct ) = @_;
    my $node = $self->_hash_fetch( { name => '_pages', key => $url } );

    my $file_loc = "$ENV{YOTE_ROOT}/html/$url";
    my $buf = '';
    if( -e $file_loc ) {
	open my $IN, '<', $file_loc;
	while(<$IN>) {
	    $buf .= $_;
	}
	close $IN;
    }
    unless( $node ) {
	$node = new Yote::RootObj( {
	    created_time => time,
	    last_saved   => time,
	    page_text    => $buf,
	    file_loc     => $file_loc,
				   } );
    }
    $node->set_working_text( $buf );
    return $node;
} #reload_from_file

sub load_page_node {
    my( $self, $url, $acct ) = @_;
    my $node = $self->_hash_fetch( { name => '_pages', key => $url } );
    die "load_page_node takes a url string" unless $url && ! ref( $url );
    unless( $node ) {
	my $file_loc = "$ENV{YOTE_ROOT}/html/$url";
	my $buf = '';
	if( -e $file_loc ) {
	    open my $IN, '<', $file_loc;
	    while(<$IN>) {
		$buf .= $_;
	    }
	    close $IN;
	}
	$node = new Yote::RootObj( {
	    created_time => time,
	    last_saved   => time,
	    page_text    => $buf,
	    file_loc     => $file_loc,
				   } );
    }
    $node->set_working_text( $node->get_page_text() );
    return $node;
} #load_page_node

sub save_page_node {
    my( $self, $node, $acct ) = @_;
    die "Argument must be a node obj" unless $node && ref( $node ) eq 'Yote::RootObj';
    $node->set_page_text( $node->get_working_text() );
    open my $OUT, '>', $node->get_file_loc() or die "File Permissions Error";
    print $OUT $node->get_page_text();
    return "Saved";
} #save_page_node

1;

__END__


=head1 NAME

Yote::Util::Pages

=head1 SYNOPSIS

=head1 METHODS

=over 4

=item reload_from_file( page name )

=item load_page_node( url )

=item save_page_node( url )

=back

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2013 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
