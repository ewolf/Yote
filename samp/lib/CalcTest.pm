package CalcTest;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;

use base 'Yote::Server::App';

use Samp::Scenario;
use Samp::Acct;

sub _acct_class { "Samp::Acct" }

# handy RESET for testing
sub reset {
    my $self = shift;
    $self->set__accts( {} );
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


             
