package Yote::IO::Mailer;

use strict;
use warnings;

use Yote::IO::SMTP;

our $MAILER;

sub init {
    my $args = shift;
    my $mail_imp = 'Yote::IO::SMTP';
    eval( "require $mail_imp" );
    $MAILER = $mail_imp->new( $args );
} #init


sub send_email {
    $MAILER->send_email( @_ );
} #send_email
    

1;

__END__

=head1 NAME

Yote::IO::Mailer

=head1 DESCRIPTION

This is the wrapper class for different mailers. Currently just Yote::IO::SMTP exists as the mailer.

=head1 PUBLIC API METHODS

=over 4
 
=item init

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
