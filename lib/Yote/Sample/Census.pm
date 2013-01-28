package Yote::Sample::Census;

use strict;

use base 'Yote::AppRoot';


sub show_count {
    my $self = shift;
    $self->set_count( 1 + $self->get_count() );
    return $self->get_count();
}


1;

__END__
