package Samp::ProductLine;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;
use base 'Yote::ServerObj';

use Samp::Step;

our ( %EditFields ) = ( map { $_ => 1 } ( 
                            qw( name
                                description  ) ) );

sub _init {
    my $self = shift;
    $self->set_name( "product" );
    $self->set_employeeds([]);
    $self->set_avg_food_cost( 0 );
    $self->set_avg_unit_sale_price( 0 );
    $self->set_avg_packaging_price( 0 );
    $self->set_fixed_cost_per( 0 );
    $self->set_steps( [] );
}

sub new_step {
    my $self = shift;
    $self->add_to_steps( $self->{STORE}->newobj( {
        product_line => $self,
                                   }, 'Samp::Step' ) );
}

# avg hours in month? est 52 weeks
# 52*40/12 --> 173 hours/month
#

sub calc {
    my $self = shift;
    my $work_hours_in_month = 173;

    # find monthly costs
    
    
    # loop thru all steps to find the bottleneck
}

sub add_employee {
    my $self = shift;
    $self->add_to_employees( $self->{STORE}->newobj( {
        name => "name",
        hourly_wage => 15,
                                                     } ) );
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
