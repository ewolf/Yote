package Yote::Util::Admin;

# app for admin control

use strict;

use base 'Yote::AppRoot';

use Yote::Util::CMS;

sub _init {
    my $self = shift;
    $self->set_cms( new Yote::Util::CMS() );
} #_init

1;

__END__

