package Samp::Scenario;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;
use base 'Yote::ServerObj';

our ( %EditFields ) = ( map { $_ => 1 } ( qw( name description  ) ) );

sub _init {
    my $self = shift;
    $self->set_employees([]);
    $self->set_equipment([]);
    $self->set_overhead(0);
    $self->set_product_lines([  
        $self->{STORE}->newobj( { name => 'product name' }, 'Samp::ProductLine' )
        ]);
} #_init

sub new_product_line {
    my $self  = shift;
    my $prods = $self->get_product_lines([]);
    my $newp  = $self->{STORE}->newobj( { name => 'product name' }, 'Samp::ProductLine' );
    
    push @$prods,  $newp;
    $newp;
} #new_product_line

sub update {
    my( $self, $fields ) = @_;
    for my $field (keys %$fields) {
        if( $EditFields{$field} ) {
            my $x = "set_$field";
            $self->$x( $fields->{$field} );
        }
    }
}

1;

__END__
