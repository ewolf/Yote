package CalcTest;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;

use base 'Yote::ServerApp';

use Samp::Scenario;

sub _init {
    my $self = shift;
}

# handy RESET for testing
sub reset {
    my $self = shift;
    $self->set_scenarios( [] );
    $self->add_entry();
}

sub add_entry {
    my $self = shift;
    my $scenarios = $self->get_scenarios([]);
    my $news = $self->{STORE}->newobj( {
        name => 'scenario ' . scalar(1 + @$scenarios),
        app  => $self,
                                   }, 'Samp::Scenario' );
    push @$scenarios, $news;
    $self->set_current_scenario( $news );
    $news;
}

sub gather {
    my $self = shift;
    my $scenes = $self->get_scenarios([]);
    return $scenes, map { $_, $_->gather } @$scenes;
}

sub setCurrentScenario {
    my( $self, $scenario ) = @_;
    $self->set_current_scenario( $scenario );
}

sub remove_entry {
    my( $self, $scenario ) = @_;
    $self->remove_from_scenarios($scenario);
    $self->set_current_scenario( $self->get_scenarios()->[0] );
} #drop_scenario

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


             
