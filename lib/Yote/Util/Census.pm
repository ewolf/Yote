package Yote::Census;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';

use base 'Yote::AppRoot';


sub show_count {
    my $self = shift;
    $self->set_count( 1 + $self->get_count() );
    return { r => $self->get_count() };
}


1;

__END__
