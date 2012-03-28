package Yote::YoteRoot;

use base 'Yote::AppRoot';

use strict;

# there can be only one

sub init {
    my $self = shift;
    $self->set_alias({});
}

sub alias_to_xpath {
    my( $self, $alias_path ) = @_;
    
}

1;
