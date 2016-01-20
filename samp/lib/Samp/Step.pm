package Samp::Step;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;
use base 'Yote::ServerObj';

our ( %EditFields ) = ( map { $_ => 1 } ( 
                            qw( name
                                description
                                units_produced
                                hours
  ) ) );


sub _init {
    my $self = shift;
    $self->set_unit_per_hour( 0 );
    $self->set_overhead_time( 0 );
    $self->set_min_time( 0 );
}

sub calculate {
    my $self = shift;
    my $hours = $self->get_hours();
    if( $hours > 0 ) {
        $self->set_production_rate( $self->get_units_produced() / $self->get_hours() );
    } else {
        $self->set_production_rate( 'n/a' );
    }
    $self->get_product_line()->calculate();
}

sub update {
    my( $self, $fields ) = @_;
    for my $field (keys %$fields) {
        if( $EditFields{$field} ) {
            my $x = "set_$field";
            $self->$x( $fields->{$field} );
        }
    }
    $self->calculate();
}


1;
