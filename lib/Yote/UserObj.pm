package Yote::UserObj;

# anyone may read public ( not starting with _ ) fields 
# but only root and object creator may see private fields 
# or edit any fields.

use strict;
use warnings;

use base 'Yote::Obj';

sub new_with_same_permissions {
    my( $self, $dummy, $account ) = @_;
    die "Permissions Error" unless $self->_check_access( $account, 1, '' );
    return new Yote::UserObj();
} #new_with_same_permissions


sub _check_access {
    my( $self, $account, $write_access, $name ) = @_;
    return ( index( $name, '_' ) != 0 && $write_access == 0 ) ||
	( $account && ( $account->_is( $self->get___creator() ) || $account->is_root() ) );
} #_check_access

1;

__END__

=head1 NAME

Yote::UserObj

=head1 DESCRIPTION

This is a subclass of Yote::Obj that allows root or its creator to access and write to public and private fields.
Public fields may be read by others but not written. The Yote::YoteRoot instance method new_root_obj
returns a new object of this type.

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2012 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
