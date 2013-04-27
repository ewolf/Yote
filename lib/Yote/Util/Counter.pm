package Yote::Util::Counter;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';

use base 'Yote::AppRoot';

sub _init {
    my $self = shift;
    $self->set__counts( {} );
}

sub increment {
    my( $self, $data, $account, $env ) = @_;
    my $ip = $env->{ REMOTE_ADDR };
    my $count = $self->get__counts()->{$data} + 1; 
    $self->get__counts()->{$data} = $count; 
    return $count;
}

sub pages {
    my( $self,$data, $account, $env ) = @_;
    return [ keys %{$self->get__counts()} ];
}

sub count {
    my( $self,$data, $account, $env ) = @_;
    return $self->get__counts()->{$data};    
}

1;

__END__

=head1 PUBLIC METHODS

=over 4

=item count( page )

Returns the count that ws set for the page.

=item increment( page )

Increments the value associated with the count and returns the incremented value.

=item pages()

Returns a list of pages that the Counter has been given.

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
