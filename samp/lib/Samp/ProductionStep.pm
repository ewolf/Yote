package Samp::ProductionStep;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

# calculated - avail_employees, avail_equipment, production_rate, yield, (if is bottleneck calculated by Product)

sub _allowedUpdates {
    [ qw(
        name
        notes

        produced_in_run
        run_mins
        fail_rate
        min_run_time

        number_employees_required
      ) ]
} #allowedUpdates

sub _init {
    my $self = shift;
    $self->SUPER::_init;
    $self->absorb( {
        produced_in_run => 0,
        run_mins        => 0,
        fail_rate       => 0,
        min_run_time    => 0,  # calculated
        production_rate => 0,  # calculated
        yield           => 0,  # calculated

        is_bottleneck   => 0,  # calculated

        number_employees_required  => 0,
        employee2assign     => {},
        equip2assign       => {},
        employees_assignments  => [],  # calculated
        equipment_assignments  => [],  # calculated
        messages => '',                # calculated
        valid    => 0,                 # valid
                   } );
} #_init

sub _lists {
    {
        # Samp::Assignment - item, true or false
        employees_assigned   => 'Samp::Assignment',
        equipment_assigned   => 'Samp::Assignment',
    };
}


sub run_time {
    my( $self, $quan ) = @_;
    my $min  = $self->get_min_run_time;
    my $rate = $self->get_production_rate;
    return $min unless $rate;
    my $time = $quan / $rate;
    return $min > $time ? $min : $time;
}

sub employees {
    my $self = shift;
    my $prodline = $self->get_parent;
    my $scene = $prodline->get_parent;

    my %my_emps  = map  { $_->{ID} => $_ } @{$self->get_step_employees([])};

    return grep { ! $my_emps{$_->{ID}} } @{$scene->get_employees};

} #employees

sub calculate {
    my $self = shift;
    my $hours = $self->get_run_mins() / 60;
    if( $hours > 0 ) {
        my $rate =  $self->get_produced_in_run() / $hours ;
        $self->set_production_rate( $rate );                             # ***** VARSET *****
        $self->set_yield( $rate - $rate * $self->get_failure_rate/100 ); # ***** VARSET *****
    } else {
        $self->set_yield( 0 );
        $self->set_production_rate(0);
    }

    my $prodline = $self->get_parent;
    my $scene    = $prodline->get_parent;

    # calculate assignments for employees and equipment
    my $avail_emps = $scene->get_employees();
    my $e2a = $self->get_employee2assign;

    my $assigned_employees = 0;
    for my $emp (@$avail_emps) {
        $e2a{ $emp } //= [ $emp, 0 ];
        $assigned_employees++ if $e2a{ $emp }[1];
    }
    $self->set_employees_assignments( [values %$e2a] );

    my $avail_equip = $scene->get_equipment();
    $e2a = $self->get_equip2assign;
    for my $eq (@$avail_equipe) {
        $e2a{ $eq } //= [ $eq, 0 ];
    }
    $self->set_equipment_assignments( [values %$e2a] );

    
    my $msg = '';
    my $valid = 1;
    if( $self->get_number_employees_required > $assigned_employees ) {
        $msg = 'Not enough employees assigned';
        $valid = 0;
    }
    $self->set_messages( $msg );
    $self->set_valid( $valid );
    
    $prodline->calculate('from_ProductStep');
} #calculate

1;
