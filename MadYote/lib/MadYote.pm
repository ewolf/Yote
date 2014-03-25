package MadYote;

use strict;
use warnings;

use Yote::Obj;
use Yote::RootObj;

use base 'Yote::AppRoot';

sub _init {
    my $self = shift;
    $self->set_chat( new Yote::Obj() );
    $self->set_suggestion_box( new Yote::Obj() );
    $self->set_yote_blog( new Yote::RootObj() );
    $self->set_sandbox( new Yote::Obj() );
    $self->SUPER::_init();
}
sub _load {
    my $self = shift;
    $self->get_sandbox( new Yote::Obj() );
}
sub reset_sandbox {
    my $self = shift;
    $self->set_sandbox( new Yote::Obj() );
}


1;

__END__
