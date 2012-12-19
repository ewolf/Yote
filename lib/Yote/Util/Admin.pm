package Yote::Util::Admin;

# app for admin control

use strict;

use Yote::Util::CMS;

sub _init {
    my $self = shift;
    $self->set_cms( new Yote::Util::CMS() );
} #_init


