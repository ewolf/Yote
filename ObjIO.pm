package GServ::ObjIO;

#
# This stows and fetches G objects from a database store and provides object ids.
#

use strict;
use feature ':5.10';

use Data::Dumper;

our $SINGLETON;

sub init {
    my $args = ref( $_[0] ) ? $_[0] : { @_ };
    my $ds = $args->{datastore};
    eval("use $ds");
    die $@ if $@;
    $SINGLETON = $ds->new( $args );
} #init

sub _get_singleton {
    die "fatal: ObjIO did not run init" unless $SINGLETON;
    return $SINGLETON;
}

sub reconnect {
    return _get_singleton()->reconnect(@_);
} #reconnect

sub init_datastore {
    return _get_singleton()->init_datastore(@_);
} #init_datastore

#
# Returns the number of entries in the data structure given.
#
sub xpath_count {
    return _get_singleton()->xpath_count(@_);
} #xpath_count

#
# Returns a single value given the xpath (hash only, and notation is slash separated from root)
# This will always query persistance directly for the value, bypassing objects.
# The use for this is to fetch specific things from potentially very long hashes that you don't want to
#   load in their entirety.
#
sub xpath {
    return _get_singleton()->xpath(@_);
} #xpath

#
# Returns a list of objects as a result : All objects connected to the one specified
# by the id.
#
# The objects are returned as array refs with 3 fields :
#   id, class, data
#
sub fetch_deep {
    return _get_singleton()->fetch_deep(@_);
} #fetch_deep

#
# Returns a single object specified by the id. The object is returned as a hash ref with id,class,data.
#
sub fetch {
    return _get_singleton()->fetch(@_);
} #fetch

#
# Given a class, makes new entry in the objects table and returns the generated id
#
sub get_id {
    return _get_singleton()->get_id(@_);
} #get_id

#
# Stores the object to persistance. Object is an array ref in the form id,class,data
#
sub stow {
    return _get_singleton()->stow(@_);
} #stow


1;
__END__

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
