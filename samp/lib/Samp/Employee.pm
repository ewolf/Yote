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
    print STDERR Data::Dumper->Dump([$self->get_steps(),"WHEN ADDED STEPS?"]);
}
sub _when_removed {
    my( $self, $fromObj, $listName, $moreArgs ) = @_;
    if( $listName eq 'step_employees' ) {
        $self->remove_from_steps( $fromObj );
    }
    if( $listName eq 'employees' ) {
        print STDERR Data::Dumper->Dump([$self->get_steps(),"WHEN REMOVED STEPS?"]);
        for my $step ( @{$self->get_steps([])} ) {
            $step->remove_from_step_employees( $self );
        }
    }
}

sub calculate {
    my $self = shift;
    my $scene = $self->get_parent;
    $scene->calculate;
}

1;
