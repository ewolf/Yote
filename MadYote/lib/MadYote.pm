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
    $self->set_rolodex( new Yote::Obj() );
    $self->set_page( new Yote::RootObj() );
    $self->SUPER::_init();
}

sub reset_sandbox {
    my $self = shift;
    $self->set_sandbox( new Yote::Obj() );
}

sub precache {
    my( $self, $data, $account ) = @_;
    return [ $self->get_chat(), $self->get_suggestion_box(), $self->get_yote_blog(), 
	     $self->get_sandbox(), $self->get_page()->get_todos(), $self->get_page(), $self->get_page()->get_todos(), @{ $self->get_page()->get_todos() || [] }, $self->get_rolodex() ];
} #_precache

1;

__END__
