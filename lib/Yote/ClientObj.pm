package Yote::ClientObj;

use strict;

use Yote::Obj;

use base 'Yote::AppRoot';

use vars qw($VERSION);

$VERSION = '0.01';

sub new_obj {
    my( $self ) = @_;
    my $new = new Yote::Obj();
    
    
} #new_obj

sub set {
    my( $self, $data, $acct_root, $acct ) = @_;
}

sub get {
    my( $self, $data, $acct_root, $acct ) = @_;
}

1;

__END__

=head1 NAME

    Yote::ClientObj

=head1 SYNOPSIS

ClientObj objects provide methods for apps to be developed entirely on the client side.

=head3 INSTANCE METHODS

=over 4

=item get( key ) - Returns the item specified by the key

=item set( key, value ) - sets the item specified by the key

=back
