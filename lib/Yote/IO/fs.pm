package Yote::IO::fs;
use strict;
use parent 'Yote::IO::FixedStore';
sub new {
    my $pkg   = shift;
    my $class = ref( $pkg ) || $pkg;
    return bless {},$class;
}

1;
