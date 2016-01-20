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
    $self->set_product_lines([]);
}

sub update {
    my( $self, $fields ) = @_;
    print STDERR Data::Dumper->Dump([$self,$fields]);
    for my $field (keys %$fields) {
        if( $EditFields{$field} ) {
            my $x = "set_$field";
            $self->$x( $fields->{$field} );
        }
    }
}

1;

__END__
