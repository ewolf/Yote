package Yote::IO::Mailer;

use strict;
use warnings;

use Yote::IO::SMTP;

our $MAILER;

sub init {
    my $args = ref( $_[0] ) ? $_[0] : { @_ };
    my $mail_imp = 'Yote::IO::SMTP';
    eval( "require $mail_imp" );
    $MAILER = $mail_imp->new( $args );
} #init


sub send_email {
    $MAILER->send_email( @_ );
} #send_email
    

1;

__END__
