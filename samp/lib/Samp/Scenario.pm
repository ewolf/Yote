package Samp::Scenario;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;
use base 'Yote::ServerObj';

our %EditFields = (
    name => 1,
    );

sub _init {
    my $self = shift;
    $self->set_employees([]);
    $self->set_overhead(0);
    $self->set_product_lines([]);
}

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
