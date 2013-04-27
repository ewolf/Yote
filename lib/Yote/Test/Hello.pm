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
    $self->get_my_hash( { store => { AnObject => new Yote::Obj( { flavor => 'blueberry' } ) } } );
}

sub _load {
    my $self = shift;
    $self->set_my_hash( { store => { AnObject => new Yote::Obj( { flavor => 'blueberry' } ) } } );
    Yote::ObjProvider::stow_all();
}

sub hello {
    my( $self, $data, $acct ) = @_;
    $self->set_count( 1 + $self->get_count( 0 ) );
    return "hello there '".$data->{name}."'. I have said hello ".$self->get_count()." times.";
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

__END__

=head1 PUBLIC METHODS

=over 4

=item hello

=item hash

=item list

=item hello_scalar

=item hello_array

=item hello_hash

=item hello_nothing

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
