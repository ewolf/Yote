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
sub init {
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
}

sub Upload {
    my( $self, $data, $acct ) = @_;
    print STDERR Data::Dumper->Dump([$data,"TANL"]);
    $self->set_File( $data->{somefile} );
    return $self->get_File();
}

1;

__END__
