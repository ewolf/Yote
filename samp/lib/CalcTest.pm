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

sub fetch_scenario {
    my( $self, $idx ) = @_;
    my $scens = $self->get_scenarios([]);
    if( $idx > $#$scens || $idx < 0 ) {
        die "Invalid scenario index";
    }
    return $scens->[$idx];
}

sub reset {
    my $self = shift;
    $self->set_scenarios( [ $self->new_scene() ] );
}

sub setCurrentScene {
    my( $self, $scene ) = @_;
    $self->set_current_scene( $scene );
}

sub drop_scene {
    my( $self, $scene ) = @_;
    my $scenes = $self->get_scenarios([]);
    if( $scene && @$scenes > 1 ) {
        for( my $i=0; $i<@$scenes; $i++ ) {
            if( $scene eq  $scenes->[$i] ) {
                splice @$scenes, $i, 1;
                last;
            }
        }
        $self->set_current_scene( $scenes->[0] );
    }
} #drop_scene

sub new_scene {
    my $self = shift;
    my $scenes = $self->get_scenarios([]);
    my $news = $self->{STORE}->newobj( {
        name => 'scenario ' . scalar(1 + @$scenes),
        app  => $self,
                                   }, 'Samp::Scenario' );
    push @$scenes,  $news;
    $self->setCurrentScene( $news );
    $news;
}

sub calc { 
    my( $self, @data ) = @_;

    # 1 get the incoming 

    $self->set_calcResult( $data[0] + $data[1] );
    $self->set_hourCost( 12 );

    print STDERR Data::Dumper->Dump(["CALC", \@data]);
    return $self;
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


             
