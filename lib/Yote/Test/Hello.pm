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
    my( $self, $data, $acct ) = @_;
    $self->set_count( $self->get_count( 0 ) + 1 );
    $self->set_my_hash( {  foo    => "BAR",
			   llamas => [ "Like", "To", "Play", "With", "Twigs" ],
			   store  => { AnObject => new Yote::Obj(),
				       ANumber  => 22,
			   },
			} );
    $self->get_my_hash()->{ store }->{ AnObject }->set_flavor( "blueberry" );
    return "hello there '".$acct->get_handle()."'. I have said hello ".$self->get_count()." times.";
}

sub hash {
    my( $self, $hash ) = @_;
    return $hash->{foo};
}

sub list {
    my( $self, $list ) = @_;
    return scalar( @{ $list } );
}


sub hello_scalar {
  return "Hello"
}
sub hello_array {
    return [ "A", "B", 33 ];
}
sub hello_hash {
    return { Foo => "BAR", 
	     Baz => "BAF" }
}
sub hello_nothing {}

1;
