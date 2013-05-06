package Yote::Test::TestAppNeedsLogin;

#
# created for the html unit tests
#

use strict;

use warnings;

use Yote::Obj;
use Yote::Test::TestAppNoLogin;

use base 'Yote::AppRoot';

use vars qw($VERSION);

$VERSION = '0.02';

sub _init {
    my $self = shift;
    $self->set_yote_obj( new Yote::Test::TestAppNoLogin() );
    $self->get_yote_obj()->set_name( "INITY" );
    $self->set_auto_listy( [ "A", "B", "C" ] );
    $self->set_auto_hashy( { "foo" => "bar", "baz" => "baf" } );
    $self->set_Text( 'inity' );
    $self->set_zap( "zappy" );
}

sub purge_app {
    my $self = shift;
    $self->_init();
}

sub _allows {
    my( $app, $command, $data, $acct, $obj ) = @_;
    return defined( $acct );
}

#
# need subs to return : scalars, lists, hashes, g-objects
#
sub scalar {
    my( $self, $data, $acct ) = @_;
    die "Need account" unless $acct;
    return "ZEEP";
}

sub make_obj {
    my( $self, $data, $acct ) = @_;
    die "Need account" unless $acct;
    my $o = new Yote::Obj;
    $o->set_Text( $data->{Text} );
    $o->set_bext( "Something else" );
    # need to add the created underneath this app,
    # otherwise, the app won't be able to fetch it since its not in the apps tree
    $self->add_to_made( $o );
    return $o;
}

sub obj_text {
    my( $self, $data, $acct ) = @_;
    die "Need account" unless $acct;
    my $o = $self->get_obj();
    return $o ? $o->get_Text() : '';
}

sub give_obj {
    my( $self, $data, $acct ) = @_;
    die "Need account" unless $acct;
    $self->set_obj( $data );
    return '';
}

sub nologin_obj {
    my( $self, $data, $acct ) = @_;
    die "Need account" unless $acct;
    return $self->get_yote_obj();
}

sub list {
    my( $self, $dummy, $acct ) = @_;
    die "Need account" unless $acct;
    return $self->get_auto_listy();
}

sub hash {
    my( $self, $dummy, $acct ) = @_;
    die "Need account" unless $acct;
    return $self->get_auto_hashy();
}

sub array {
    my( $self, $data, $acct ) = @_;
    die "Need account" unless $acct;
    return [ 'A', { inner => [ 'Juan', { peanut => 'Butter', ego => $self->get_yote_obj() }] }, $self->get_yote_obj(),
	     [ qw/ b a d e f c / ]
	];
}


sub update {
    my( $self, $data, $acct ) = @_;
    die "Need account" unless $acct;
    if( $data->{Text} ) {
	$self->set_Text( $data->{Text} );
    }
}

# @TODO - should not have a sub starting with get_. refactor test
sub SDFfetch_hash {
    my( $self, $data, $acct_root, $acct ) = @_;
    die "Need account" unless $acct;
    return { hash => "is something like", wid => $self->get_yote_obj() };
}

sub reset {
    my( $self, $data, $acct ) = @_;
    die "Need account" unless $acct;
    $self->set_obj( undef );
    $self->set_made([]);
    $self->set_auto_listy( [ "A", "B", "C" ] );
    $self->set_auto_hashy( { "foo" => "bar", "baz" => "baf" } );

}

sub long_time {
    sleep( 5 );
    return "Long";
}
sub short_time {
    return "short";
}
sub medium_time {
    sleep( 2 );
    return "Med";
}

1;

__END__


=head1 PUBLIC METHODS

=over 4

=item scalar

=item make_obj

=item obj_text

=item give_obj

=item nologin_obj

=item list

=item hash

=item array

=item get_hash

=item reset

=item long_time

=item short_time

=item medium_time

=item purge_app

=item update

=item SDFfetch_hash

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
