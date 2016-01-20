package Samp::Ingredient;


use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _allowedUpdates {
    [ qw( product
          notes
          amount_per_run
       ) ]
}

sub _when_added {
    my( $self, $toProduct, $listName, $itemArgs ) = @_;
    $self->set_product( $itemArgs );
}


1;
