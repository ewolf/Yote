package Samp::RawMaterial;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

use Samp::Step;
use Samp::Ingredient;

sub _allowedUpdates {
    [ qw( name 
          notes

          cost_unit
          units_batch
       ) ]
}
sub _init {
    my $self = shift;
    $self->SUPER::_init;
    $self->set_cost_unit( 0 );
    $self->set_units_batch( 0 );
} #_init

sub calculate {
    # calculate redux
    my $self = shift;

    $self->set_cost( $self->get_cost_unit * $self->get_units_batch );
    
    $self->get_parent->calculate;
    
} #calculate


1;

__END__
