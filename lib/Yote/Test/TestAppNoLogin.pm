package Yote::Test::TestAppNoLogin;

#
# created for the html unit tests
#

use strict;

use Yote::Obj;

use base 'Yote::AppRoot';

use vars qw($VERSION);

$VERSION = '0.01';

#
# need subs to return : scalars, lists, hashes, g-objects
#

sub scalar {
    my( $self, $data, $acct_root, $acct ) = @_;
    return "BEEP";
}

sub apply_zap {
    my( $self, $data, $acct_root, $acct ) = @_;
    $self->set_zap( $data );
}

sub reset {
    my $self = shift;
    $self->set_zap( undef );
}

1;

__END__
