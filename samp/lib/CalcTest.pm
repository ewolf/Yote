package CalcTest;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;

use base 'Yote::Server::App';

use Samp::Scenario;

sub _init {
    my $self = shift;
    $self->SUPER::_init();
    $self->add_entry( 'scenarios' );
}

sub _allowedUpdates {
    'current_scenario';
}

sub _lists {
    {
        scenarios => 'Samp::Scenario',
    };
}

sub calculate {
    my( $self, $type, $listName, $scen, $idx ) = @_;
    if( $listName eq 'scenarios' ) {
        if( $type eq 'new_entry' ) {
            $self->set_current_scenario( $scen );
        } elsif( $type eq 'removed_entry' ) {
            my $sc = $self->get_scenarios;
            if( @$sc ) {
                $self->set_current_scenario( $idx > $#$sc ? $sc->[$#$sc] : $sc->[$idx] );
            } else {
                $self->set_current_product_line( undef );
            }
        }
    }
}

# handy RESET for testing
sub reset {
    my $self = shift;
    $self->set_scenarios( [] );
    $self->add_entry( 'scenarios' );
}

1;

__END__


the purpose of this is to improve efficency for
a production process.

this estimates the bottlenecks in a process and
calculates the max rate given the resources
available

>>>><<<<<

{shop:
    employees:
         <add new>
    products:
         wedding cakes
         store cakes
         chocolates


shop has the following features :

    employees : <designation,hourly cost>

for example, for chococlates :

    produces : chocolates
   
    avg food cost : %
    avg packaging cost : %

    unit sale

    max units that can be stored

    the pipeline has the following steps :
          making fillings ( caramel, etc )

          tempering chocolate & enrobing

          packaging

    each step of the way notes how many employees it takes


             
