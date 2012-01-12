package GServ::TestAppNeedsLogin;

#
# created for the html unit tests
#

use strict;

use GServ::Obj;

use base 'GServ::AppRoot';

use vars qw($VERSION);

$VERSION = '0.01';

sub init {
    my $self = shift;
    $self->set_gserv_obj( new GServ::TestAppNoLogin() );
    $self->get_gserv_obj()->set_name( "INITY" );
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
    return $self->get_gserv_obj();
}

sub get_array {
    my( $self, $data, $acct ) = @_;
    return [ 'A', { inner => [ 'Juan', { peanut => 'Butter', ego => $self->get_gserv_obj() }] }, $self->get_gserv_obj()  ];
}

sub get_hash {
    my( $self, $data, $acct ) = @_;
    return { hash => "is something like", wid => $self->get_gserv_obj() };
}

1;

__END__
