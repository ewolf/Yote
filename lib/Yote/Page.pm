package Yote::Page;

use strict;
use warnings;

use parent 'Yote::Obj';

sub _init {
    my $self = shift;
    $self->set__pages( [] );
} #_init

sub fetch_page {
    my( $self, $url ) = @_;
    my $node = $self->_hash_fetch( '_pages', $url );
    my $file_loc = "$ENV{YOTE_ROOT}/html/$url";
    if( -e $file_loc ) {
	
    }
    elsif( $node ) {
	
    }
    else {
	# 404
    }
} #fetch_page

1;

__END__


The idea is to have a page object that keeps track of versions of web
pages written to disc. This would allow versioned pages to be edited
using a web front end easily.

This would have a method to get a page. It would check to see if
the latest version it has in is newer or older than the one on disc.
if newer, the disc one is overwritten. if older, a new version is
created that becomes the current version.

so fields :

Yote::Page
     pages -> { pagename => Yote::Obj with {   current_version => Yote::Obj, versions => [ ... ] }

old versions should be able to be deleted.

methods :
   _fetch_page. Private.. an app is expected to call this.
   


