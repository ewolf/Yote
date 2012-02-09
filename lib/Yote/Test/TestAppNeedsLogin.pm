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
    my( $self, $data, $acct_root, $acct ) = @_;
    return "ZEEP";
}

sub make_obj {
    my( $self, $data, $acct_root, $acct ) = @_;
    my $o = new Yote::Obj;
    $o->set_text( $data->{text} );
    # need to add the created underneath this app,
    # otherwise, the app won't be able to fetch it since its not in the apps tree
    $self->add_to_made( $o );
    return $o;
}

sub obj_text {
    my $self = shift;
    my $o = $self->get_obj();
    return $o ? $o->get_text() : '';
}

sub give_obj {
    my( $self, $data, $acct_root, $acct ) = @_;
    print STDERR Data::Dumper->Dump( ["Give OBJ",$data] );
    $self->set_obj( $data );
    return '';
}

sub get_nologin_obj {
    my( $self, $data, $acct_root, $acct ) = @_;
    return $self->get_yote_obj();
}

sub get_array {
    my( $self, $data, $acct_root, $acct ) = @_;
    return [ 'A', { inner => [ 'Juan', { peanut => 'Butter', ego => $self->get_yote_obj() }] }, $self->get_yote_obj()  ];
}

sub get_hash {
    my( $self, $data, $acct_root, $acct ) = @_;
    return { hash => "is something like", wid => $self->get_yote_obj() };
}

1;

__END__
