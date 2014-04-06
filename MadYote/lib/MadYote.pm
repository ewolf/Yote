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
    $self->set_page( new Yote::RootObj() );
    $self->SUPER::_init();
}
sub _load {
    my $self = shift;
    $self->get_sandbox( new Yote::Obj() );
    $self->get_rolodex( new Yote::Obj() );
    $self->get_page( new Yote::RootObj() );
}
sub reset_sandbox {
    my $self = shift;
    $self->set_sandbox( new Yote::Obj() );
}


1;

__END__
