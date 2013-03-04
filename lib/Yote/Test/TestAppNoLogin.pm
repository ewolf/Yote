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
sub _init {
    my $self = shift;
    $self->set_File( undef );
}

sub scalar {
    my( $self, $data, $acct ) = @_;
    return "BEEP";
}

sub apply_zap {
    my( $self, $data, $acct ) = @_;
    $self->set_zap( $data );
}

sub reset {
    my $self = shift;
    $self->set_zap( undef );
    $self->set_Files( [] );
    $self->set_File( undef );
}

sub UpOne {
    my( $self, $data, $acct ) = @_;
    $self->set_File( $data->{somefile_3} );
}

sub Upload {
    my( $self, $data, $acct ) = @_;
    $self->add_to_Files( $data->{somefile} );
    $self->add_to_Files( $data->{somefile_2} );
}

1;

__END__
