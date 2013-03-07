package Yote::Test::Hello;

use strict;

use Yote::Obj;

use base 'Yote::AppRoot';

use vars qw($VERSION);

$VERSION = '0.01';

sub _init {
    my $self = shift;

    $self->set_testfield(int(rand(10)));
    $self->get_list( [ 1, "Bagel" ] );
    $self->get_hash( { one=>1, food => "Bagel" } );
}

sub hello {
    my( $self, $data, $acct_root, $acct ) = @_;
    $self->set_count( $self->get_count( 0 ) + 1 );
    $self->set_my_hash( {  foo    => "BAR",
			   llamas => [ "Like", "To", "Play", "With", "Twigs" ],
			   store  => { AnObject => new Yote::Obj(),
				       ANumber  => 22,
			   },
			} );
    $self->get_my_hash()->{ store }->{ AnObject }->set_flavor( "blueberry" );
    return "hello there";
}

sub hash {
    my( $self, $hash ) = @_;
    return $hash->{foo};
}

sub list {
    my( $self, $list ) = @_;
    return scalar( @{ $list } );
}

1;
