package Samp::Employee;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _allowedUpdates {
    [ qw(
        name 
        notes
        hourly_pay
        hours_per_week
      ) ]
} #allowedUpdates

sub _lists { #steps that this employee performs
    { 
        steps       => 'Samp::Step',
    };
}


sub _when_added {
    my( $self, $toObj, $listName, $moreArgs ) = @_;
    if( $listName eq 'step_employees' ) {
        $self->add_to_steps( $toObj );
    }
}
sub _when_removed {
    my( $self, $fromObj, $listName, $moreArgs ) = @_;
    if( $listName eq 'step_employees' ) {
        $self->remove_from_steps( $fromObj );
    }
    if( $listName eq 'employees' ) {
        # this is disallowed if this employee is in a step

        #ugh, this can't work unless when_removed is executed before the removal
        die "Cannot remove this employee. This employee performs a production step" if @{$self->get_steps([])} > 0;
    }
}

sub calculate {
    my $self = shift;
    my $scene = $self->get_parent;
    $scene->calculate;
}

1;
