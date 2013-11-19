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
}

1;

__END__
