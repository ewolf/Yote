package Yote::Util::Pages;

########################################################################
# Pages is a utility for editing and versioning the pages on the site. #
# Author : Eric Wolf						       #
########################################################################

use strict;
use warnings;

use base 'Yote::AppRoot';

use Yote::RootObj;


sub _init {
    my $self = shift;
    $self->set__pages({});
}

sub load_page_node {
    my( $self, $url, $acct ) = @_;
    my $node = $self->hash_fetch( { name : '_pages', key : $url } );
    die "load_page_node takes a url string" unless $url && ! ref( $url );
    unless( $node ) {
	my $file_loc = "$ENV{YOTE_ROOT}/html/$url";
	my $buf = '';
	if( -e $html_loc ) {
	    open my $IN, '<', $html_loc;
	    while(<$IN>) {
		$buf .= $_;
	    }
	    close $IN;
	}
	$node = new Yote::RootObj( {
	    created_time => time,
	    page_text    => $buf,
	    file_loc     => $file_loc,
				   } );
    }
    return $node;
} #load_page_node

sub save_page_node {
    my( $self, $node, $acct ) = @_;
    die "Argument must be a node obj" unless $node && ref( $node ) eq 'Obj::RootObj';
    open my $OUT, '>', $node->get_file_loc() or die "File Permissions Error";
    print $OUT $node->get_page_text();
    return "Saved";
} #save_page_node

1;

__END__
