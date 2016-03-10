package Samp::ProductionStep;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

use Samp::Assign;

# calculated - avail_employees, avail_equipment, production_rate, yield, (if is bottleneck calculated by Product)

sub _allowedUpdates {
    qw(
        name
        notes

        number_produced_in_timeslice
        timeslice_mins
        fail_rate
        min_run_time

        number_employees_required
      );
} #allowedUpdates

sub _init {
    my $self = shift;
    $self->SUPER::_init;
    $self->absorb( {
        number_produced_in_timeslice => 0,
        timeslice_mins        => 0,
        fail_rate       => 0,
        min_run_time    => 0,  # calculated
        production_rate => 0,  # calculated
        yield           => 0,  # calculated

        is_bottleneck   => 0,  # calculated

        number_employees_required  => 1,
        _employee2assign     => {},
        _equip2assign       => {},
        messages => '',                # calculated
        valid    => 0,                 # valid
                   } );
} #_init

sub run_time {
    my( $self, $quan ) = @_;
    my $min  = $self->get_min_run_time / 60;
    my $rate = $self->get_production_rate;
    return $min unless $rate;
    my $time = $quan / $rate;
    return $min > $time ? $min : $time;
}

sub _max_batch_size {
    my $self = shift;
    my $e2a = $self->get__equip2assign;    

    #
    # calculates out how many batches can be done in parallel
    # and multiplies the max batch size of the equipment by how many times in parallel
    #
    my $emps2a = $self->get__employee2assign;
    my( $emps_avail ) = scalar( grep { $_->get_is_used } values %$emps2a );

    my $emps_reqd = $self->get_number_employees_required;
    my( @equips ) = ( sort { $b->get_max_batch_size <=> $a->get_max_batch_size }
                      map  { $_->get_item } 
                      grep { $_->get_is_used } 
                      values %$e2a );

    # if no employees are required ( say for a long baking step ), the parallel number is the same
    # as the amount of equipment
    my $parallel_teams = $emps_reqd ? int( $emps_avail / $emps_reqd ) : scalar( @equips );
    my $parallel_runs = @equips > $parallel_teams ? $parallel_teams : @equips;

    my $max = 0;
    for( 1 .. $parallel_runs ) {
        $max += $equips[ $_ - 1 ]->get_max_batch_size;
    }
    $max;
} #_max_batch_size

sub calculate {
    my $self = shift;
    my $hours = $self->get_timeslice_mins() / 60;
    if( $hours > 0 ) {
        my $rate =  $self->get_number_produced_in_timeslice() / $hours ;
        $self->set_production_rate( $rate );                             # VARSET *****
        $self->set_yield( $rate - $rate * $self->get_failure_rate/100 ); # VARSET *****
    } else {
        $self->set_yield( 0 );
        $self->set_production_rate(0);
    }

    my $prodline = $self->get_parent;
    my $scene    = $prodline->get_parent;

    #
    # Calculate assignments for employees and equipment. Note that for a step, at most
    # one piece of equipment is allowed (combine more than one piece of equipment for hybrid pieces).
    # however, more than one may be available. For example, there might be :
    #  20 qt mixer I
    #  60 qt mixer I
    #  60 qt mixer II
    #
    # any of which can be used
    #
    my $avail_emps  = $scene->get_employees;
    my $emps2assign = $self->get__employee2assign;

    my $assigned_employees = 0;
    my %seen;
    for my $emp (@$avail_emps) {
        $seen{$emp} = 1;   # employee, is available
        my $as = $emps2assign->{ $emp } //= $self->{STORE}->newobj( { item => $emp }, 'Samp::Assign' );
        $assigned_employees++ if $as->get_is_used;
    }

    # filter out removed items
    for my $delme ( grep { ! $seen{$_} } keys %$emps2assign ) {
        delete $emps2assign->{$delme};
    }

    my $avail_equip = $scene->get_equipment;
    my $equip2assign = $self->get__equip2assign;
    %seen = ();
    for my $eq (@$avail_equip) {
        $seen{ $eq } = 1; # equipment, used
        $equip2assign->{ $eq } //= $self->{STORE}->newobj( { item => $eq }, 'Samp::Assign' );
    }
    # filter out removed items
    for my $delme ( grep { ! $seen{$_} } keys %$equip2assign ) {
        delete $equip2assign->{$delme};
    }

    $self->set_max_batch_size( $self->_max_batch_size ); # VARSET *****

    my $msg = '';
    my $valid = 1;
    if( $self->get_number_employees_required > $assigned_employees ) {
        $msg = 'Not enough employees assigned';
        $valid = 0;
    }
    $self->set_messages( $msg );  # VARSET *****
    $self->set_valid( $valid );   # VARSET *****
    
    $prodline->calculate('from_ProductStep');
} #calculate

1;

__END__

Given 
   
