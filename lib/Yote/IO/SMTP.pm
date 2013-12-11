package Yote::IO::SMTP;

use strict;
use warnings;

use Email::Valid;
use Mail::Sender;

sub new {
    my( $pkg, $args ) = @_;
    my $class = ref( $pkg ) || $pkg;

    my $self = {
	options => { on_errors => 'die', map { s/^smtp_//; $_ => $args->{"smtp_$_"} } grep { /^smtp_/ } keys %$args }
    };
    return bless $self, $class;
} #new

sub send_email {
    my( $self, $opts ) = @_;

    my $sender = new Mail::Sender( $self->{options} );

    $sender->MailMsg( $opts );
	
} #send_email


1;

__END__


=head1 NAME

Yote::IO::SMTP

=head1 DESCRIPTION

Uses Mail::Sender to send messages with SMTP.

=head1 PUBLIC API METHODS

=item send_email( opts )

Sends a simple ( not html ) email. The opts is a hash and must contain to, from, subject and message fields.

=back

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
