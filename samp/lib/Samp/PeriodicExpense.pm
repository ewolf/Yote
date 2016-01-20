package Samp::PeriodicExpense;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _allowedUpdates {
    [ qw(
        name 
        notes
        cost
        cost_period
      ) ]
} #allowedUpdates

sub choices {
    my( $self, $field ) = @_;
    if( $field eq 'cost_period_type' ) {
        return (qw( month quarter year ));
    }
    return ();
} #choices



1;
