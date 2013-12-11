package Yote::SimpleTemplate;

use base 'Yote::Obj';

sub _fill {
    my( $self, $context ) = @_;
    
    my $txt = $self->get_text('');
    
    $txt =~ s/([^\\])\$\{([^\}]+)/$1$context->{$2}/g;
    $txt =~ s/([^\\])\\/$1/g;

    return $txt;
} #_fill

1;

__END__


=head1 NAME

Yote::SipmleTemplate - A very simple templating system on the server side.

=head1 DESCRIPTION

=head1 PUBLIC API METHODS

=over 4

=back

=head1 PUBLIC DATA FIELDS

=over 4

=back

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut

