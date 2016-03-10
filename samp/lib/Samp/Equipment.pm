package Samp::Equipment;

use strict;
use warnings;
no warnings 'uninitialized';

use base 'Yote::Server::ListContainer';

sub _allowedUpdates {
    [ qw(
        name 
        notes
        unit_type
        max_capacity
      ) ]
} #allowedUpdates



1;
