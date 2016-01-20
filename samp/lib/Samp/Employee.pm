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

sub _when_added {
    my( $self, $toObj, $listName, $moreArgs ) = @_;
    
}
sub _when_removed {
    my( $self, $fromObj, $listName, $moreArgs ) = @_;
}

1;
