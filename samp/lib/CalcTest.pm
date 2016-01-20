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
    $self->set_scenarios( [ $self->new_scene() ] );
}

sub new_scene {
    my $self = shift;
    my $scenes = $self->get_scenarios([]);
    my $news = $self->{STORE}->newobj( {
        name => 'scenario ' . scalar(1 + @$scenes),
        app  => $self,
                                   }, 'Samp::Scenario' );
    push @$scenes, $news;
    $self->set_current_scene( $news );
    $news;
}


# remove
sub setCurrentScene {
    my( $self, $scene ) = @_;
    $self->set_current_scene( $scene );
}

# remove?
sub drop_scene {
    my( $self, $scene ) = @_;
    $self->remove_from_scenarios($scene);
    $self->set_current_scene( $self->get_scenes()->[0] );
} #drop_scene
print STDERR Data::Dumper->Dump(["LODY"]);

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


             
