package Yote::RootObj;

# anyone may read public ( not starting with _ ) fields 
# but only root may see private fields or edit any fields.

use strict;
use warnings;

use parent 'Yote::Obj';

sub new_with_same_permissions {
    my( $self, $args, $account ) = @_;
    die "Permissions Error" unless $self->_check_access( $account, 1, '' );
    return new Yote::RootObj( $args );
} #new_with_same_permissions

# only root may edit any fields. public fields are readable by all.
sub _check_access {
    my( $self, $account, $write_access, $name ) = @_;
    return ( index( $name, '_' ) != 0 && $write_access == 0 ) || ( $account && $account->is_root() );
} #_check_access

1;

__END__

=head1 NAME

Yote::RootObj

=head1 DESCRIPTION

This is a subclass of Yote::Obj that allows root access of its public and private fields for reading and wrinting
and allows read access of its public fields for non root users. The Yote::YoteRoot instance method new_root_obj
returns a new object of this type.

=head2 METHODS

=over 4

=item new_with_same_permissions()

Returns a new yote object with the same permissions as this.

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
