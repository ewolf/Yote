package Samp::Ingredient;


use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _allowedUpdates {
    [ qw( product
          notes
          units_per_unit
       ) ]
}

sub _when_added {
    my( $self, $toProduct, $listName, $ingredientProduct ) = @_;
    $self->set_product( $ingredientProduct );
    $ingredientProduct->add_to_ingredient_of( $toProduct );
}


1;
