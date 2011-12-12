package GServ::AppProvider;

use strict;

use GServ::AppRoot;
use GServ::ObjProvider qw/fetch/;

use base 'GServ::ObjProvider';

sub fetch_root {
    my $root = fetch( 1 );
    unless( $root ) {
        $root = new GServ::AppRoot;
        $root->save;
    }
    return $root;
}


1;

__END__

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
