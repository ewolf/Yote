package Yote::Test::TestAppNeedsLogin;

#
# created for the html unit tests
#

use strict;

use Yote::Obj;
use Yote::Test::TestAppNoLogin;

use base 'Yote::AppRoot';

use vars qw($VERSION);

$VERSION = '0.01';

sub init {
    my $self = shift;
    $self->set_yote_obj( new Yote::Test::TestAppNoLogin() );
    $self->get_yote_obj()->set_name( "INITY" );
}

sub allows {
    my( $self, $data, $acct ) = @_;
    return defined($acct);
}

#
# need subs to return : scalars, lists, hashes, g-objects
#
sub get_scalar {
    my( $self, $data, $acct ) = @_;
    return "ZEEP";
}

sub get_nologin_obj {
    my( $self, $data, $acct ) = @_;
    return $self->get_yote_obj();
}

sub get_array {
    my( $self, $data, $acct ) = @_;
    return [ 'A', { inner => [ 'Juan', { peanut => 'Butter', ego => $self->get_yote_obj() }] }, $self->get_yote_obj()  ];
}

sub get_hash {
    my( $self, $data, $acct ) = @_;
    return { hash => "is something like", wid => $self->get_yote_obj() };
}

1;

__END__
