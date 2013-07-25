package Yote::MongoIO;

#
# This stows and fetches G objects from a database store and provides object ids.
#

use strict;
use warnings;
no warnings 'uninitialized';
no warnings 'recursion';
use feature ':5.10';

use MongoDB;

use vars qw($VERSION);

$VERSION = '0.032';

# ------------------------------------------------------------------------------------------
#      * INIT METHODS *
# ------------------------------------------------------------------------------------------
sub new {
    my $pkg = shift;
    my $class = ref( $pkg ) || $pkg;
    my $args = ref( $_[0] ) ? $_[0] : { @_ };

    my $self = {
        args => $args,
    };
    bless $self, $class;
    $self->_connect( $args );
    return $self;
} #new


# ------------------------------------------------------------------------------------------
#      * PUBLIC CLASS METHODS *
# ------------------------------------------------------------------------------------------


sub commit_transaction {}

sub client {
    return shift->{MONGO_CLIENT};
}

sub database {
    return shift->{ DB };
}

sub disconnect {} #there is no way to explicitly disconnect from the database, see perldoc for MongoDB

sub ensure_datastore { 
    # we use a single mongo collection, objects
    # The documents in this database have the following structure :
    #  { 
    #   _id : mongo id for this document ( indexed by default )
    #    d   : JSONDATA of object
    #    r   : [] list of referenced ids ( indexed )
    #    c   : class of object
    #  }
    #    
    # There is also a collection that exists soley to have a single document that 
    # contains the id of the root object. This collection is called 'root'.
    #
    #
    my $self = shift;
    $self->{ OBJS } = $self->{ DB }->get_collection( "objects" );
    $self->{ OBJS }->ensure_index( { 'r' => 1 } );

    my $root = $self->{ DB }->get_collection( "root" );
    my $root_node = $root->find_one( { root => 1 } );
    if( $root_node ) {
	$self->{ ROOT_ID } = $root_node->{ root_id };
    } else {
	my $root_id = MongoDB::OID->new;
	my $xid = $root->insert( { root => 1, root_id => $root_id->{ value } } );
	$self->{ ROOT_ID } = $root_id->{ value };
    }
} #ensure_datastore

#
# Returns the first ID that is associated with the root YoteRoot object
#
sub first_id {
    my $self = shift;
    return $self->{ ROOT_ID };
} #first_id

#
# Returns a single object specified by the id. The object is returned as a hash ref with id,class,data.
#
sub fetch {
    my( $self, $id ) = @_;
    my $data = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $id ) } );
    return unless $data;
    if( $data->{ c } eq 'ARRAY' ) {
	return [ $id, $data->{ c }, $data->{d} ];
    } else {
	my $unescaped_data = {};
	for my $key ( keys %{$data->{d}} ) {
	    my $val = $data->{d}{$key};
	    $key =~ s/\\/\./g;
	    $unescaped_data->{$key} = $val;
	}
	return [ $id, $data->{ c }, $unescaped_data ];
    }
} #fetch

#
# Returns a new ID to assign.
#
sub get_id {
    my( $self ) = @_;
    my $new_id = MongoDB::OID->new();
    return $new_id->{value};
} #get_id

#
# Returns true if the given object traces back to the root.
#
sub _has_path_to_root {
    my( $self, $obj_id, $seen ) = @_;
    return 1 if $obj_id eq $self->first_id();
    $seen ||= { $obj_id => 1 };

    my $curs = $self->{ OBJS }->find( { r => $obj_id } );
    while( my $obj = $curs->next ) {
	my $o_id = $obj->{ _id }{ value };
	next if $seen->{ $o_id }++;
	if( $self->_has_path_to_root( $o_id, $seen ) ) {
	    return 1;
	}
    }
    return 0;
} #_has_path_to_root

#
# Returns the number of entries in the list of the given id.
#
sub count {
    my( $self, $container_id ) = @_;
    my $mid = MongoDB::OID->new( value => $container_id );
    my $obj = $self->{ OBJS }->find_one( { _id => $mid } );
    if( $obj->{ c } eq 'ARRAY' ) {
	return scalar( @{$obj->{ d } } );
    }
    return scalar( keys %{$obj->{ d } } );
} #count

sub list_insert {
    my( $self, $list_id, $val, $idx ) = @_;
    my $mid = MongoDB::OID->new( value => $list_id );
    my $obj = $self->{ OBJS }->find_one( { _id => $mid } );
    die "list_delete must be called for list" if $obj->{ c } ne 'ARRAY';
    if( $obj ) {
	if( defined( $idx ) ) {
	    splice @{$obj->{ d }}, $idx, 0, $val;
	} else {
	    push @{$obj->{ d }}, $val;
	}
	$self->{ OBJS }->update( { _id => $mid, }, $obj );
    }
    return;
} #list_insert

sub hash_delete {
    my( $self, $hash_id, $key ) = @_;
    my $mid = MongoDB::OID->new( value => $hash_id );
    my $obj = $self->{ OBJS }->find_one( { _id => $mid } );
    die "hash_delete must be called for hash" if $obj->{ c } ne 'HASH';
    delete $obj->{ d }{ $key };
    if( $obj ) {
	$self->{ OBJS }->update( { _id => $mid, }, $obj );
    }
    return;
}

sub list_delete {
    my( $self, $list_id, $idx ) = @_;
    my $mid = MongoDB::OID->new( value => $list_id );
    my $obj = $self->{ OBJS }->find_one( { _id => $mid } );
    die "list_delete must be called for list" if $obj->{ c } ne 'ARRAY';
    if( $obj ) {
	splice @{$obj->{ d }}, $idx, 1;
	$self->{ OBJS }->update( { _id => $mid, }, $obj );
    }
    return;
}

sub hash_insert {
    my( $self, $hash_id, $key, $val ) = @_;
    my $mid = MongoDB::OID->new( value => $hash_id );
    my $obj = $self->{ OBJS }->find_one( { _id => $mid } );
    die "hash_insert must be called for hash" if $obj->{ c } ne 'HASH';
    $obj->{ d }{ $key } = $val;
    if( $obj ) {
	$self->{ OBJS }->update( { _id => $mid, }, $obj );
    }
    return;
} #hash_insert

sub hash_fetch {
    my( $self, $hash_id, $key ) = @_;

    my $hash = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $hash_id ) } );
    die "hash fetch must be called for hash" if $hash->{ c } ne 'HASH';
    return $hash->{ d }->{ $key } if $hash;
} 

sub list_fetch {
    my( $self, $list_id, $idx ) = @_;

    my $list = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $list_id ) } );
    die "list fetch must be called for array" if $list->{ c } ne 'ARRAY';

    return $list->{ d }->[ $idx ] if $list;
} 

sub hash_has_key {
    my( $self, $hash_id, $key ) = @_;
    my $hash = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $hash_id ) } );
    return defined( $hash->{ d }->{$key} );
}

#
# Returns a hash of paginated items that belong to the hash. 
# 
sub paginate_hash {
    my( $self, $hash_id, $paginate_length, $paginate_start ) = @_;

    my $list = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $hash_id ) } );

    my $result_data = $list->{ d };

    if( $list->{ c } eq 'ARRAY' ) {
	if( defined( $paginate_length ) ) {
	    if( $paginate_start ) {
		if( $paginate_start > $#$result_data ) {
		    return {};
		}
		if( ( $paginate_start+$paginate_length ) > @$result_data ) {
		    $paginate_length = scalar( @$result_data ) - $paginate_start;
		}
		return { map { $_ => $result_data->[ $_ ] } ( $paginate_start..($paginate_start+$paginate_length-1) ) };
	    }
	    if( $paginate_length > $#$result_data ) {
		$paginate_length = $#$result_data;
	    }
	    return { map { $_ => $result_data->[ $_ ] } ( 0..($paginate_length-1) ) };
	}
	return  { map { $_ => $result_data->[ $_ ] } ( 0..$#$result_data ) };
    }
    else {
	if( defined( $paginate_length ) ) {
	    my @keys = sort keys %$result_data;
	    if( $paginate_start ) {
		if( $paginate_start > $#keys ) {
		    return {};
		}
		if( ( $paginate_start + $paginate_length ) > @keys ) {
		    $paginate_length = scalar( @keys ) - $paginate_start;
		}
		return { map { $_ => $result_data->{ $_ } } @keys[$paginate_start..($paginate_start+$paginate_length-1)] };
	    }
	    if( $paginate_length > @keys ) {
		$paginate_length = scalar( @keys );
	    }
	    return { map { $_ => $result_data->{ $_ } } @keys[0..($paginate_length-1)] };
	}
	my @keys = sort keys %$result_data;
	return { map { $_ => $result_data->{ $_ } } @keys };
    }
} #paginate_hash

#
# Returns a hash of paginated items that belong to the list. Note that this 
# does not preserve indexes ( for example, if the list has two rows, and first index in the database is 3, the list returned is still [ 'val1', 'val2' ]
#   rather than [ undef, undef, undef, 'val1', 'val2' ]
#
sub paginate_list {
    my( $self, $list_id, $paginate_length, $paginate_start, $reverse ) = @_;

    my $list = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $list_id ) } );
    die "list pagination must be called for array" if $list->{ c } ne 'ARRAY';

    my $result_data = $reverse ? [reverse @{$list->{ d }}] : $list->{ d };

    if( defined( $paginate_length ) ) {
	if( $paginate_start ) {
	    if( $paginate_start > $#$result_data ) {
		return [];
	    }
	    if( ($paginate_start+$paginate_length) > @$result_data ) {
		$paginate_length = scalar( @$result_data ) - $paginate_start;
	    }
	    return [ @$result_data[$paginate_start..($paginate_start+$paginate_length-1)] ];
	} 
	if( $paginate_length > @$result_data ) {
	    $paginate_length = scalar( @$result_data );
	}
	return [ @$result_data[0..($paginate_length-1)] ];
    }    
    return $result_data;
} #paginate_list

sub recycle_object {
    my( $self, $obj_id ) = @_;
    $self->{ OBJS }->remove( { _id => MongoDB::OID->new( value => $obj_id ) } );
    # not going to remove the referenced links from a recycled object, as those links
    # by definition show up in other recycleable objects.
} #recycle_object

sub recycle_objects {
    my $self = shift;

    my $cursor = $self->{ OBJS }->find();

    my $rec_count = 0;
    while( my $obj = $cursor->next ) {
	my $id = $obj->{ _id }{ value };
	unless( $self->_has_path_to_root( $id ) ) {
	    $self->recycle_object( $id );
	    $rec_count++;
	}
    }
    return $rec_count;
} #recycle_object

sub start_transaction {}

sub stow_all {
    my( $self, $objs ) = @_;
    for my $objd ( @$objs ) {
	$self->stow( @$objd );
    }
} #stow_all

sub stow {
    my( $self, $id, $class, $data ) = @_;

    #
    # tease out references from the data, which can be either an array ref or a hash ref
    #
    my( @refs );
    if( $class eq 'ARRAY' ) {
	@refs = grep { index( $_, 'v' ) != 0 } @$data;
    } else {
	@refs = grep { index( $_, 'v' ) != 0 } values %$data;	
	my $escaped_data = {};
	for my $key (keys %$data ) {
	    my $val = $data->{$key};
	    $key =~ s/\./\\/g;
	    $escaped_data->{$key} = $val if $key;
	}
	$data = $escaped_data;
    }

    my $mid = MongoDB::OID->new( value => $id );
    if( $self->{ OBJS }->find_one( { _id => $mid } ) ) {
	$self->{ OBJS }->update( { _id => $mid, },
				 {
				     d   => $data,
				     c   => $class,
				     r   => \@refs,
				 } );
    }
    else {
	my $ins = $self->{ OBJS }->insert( { _id => $mid,
					     d   => $data,
					     c   => $class,
					     r   => \@refs,
					   } );
    }
    return;
} #stow

# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

sub _connect {
    my $self  = shift;
    my $args  = ref( $_[0] ) ? $_[0] : { @_ };
    my $host = $args->{ host } || 'localhost';
    $host .= ':' . ($args->{ engine_port } || 27017);
    my %mongo_args = (
	host => $host,
	);
    $mongo_args{ password } = $args->{ password } if $args->{ password };
    $mongo_args{ username } = $args->{ user } if $args->{ user };
    $self->{MONGO_CLIENT} = MongoDB::MongoClient->new( %mongo_args );
    $self->{DB} = $self->{MONGO_CLIENT}->get_database( $args->{ store } || 'yote' );
} #_connect


1;
__END__

=head1 NAME

Yote::SQLiteIO - A SQLite persistance engine for Yote.

=head1 DESCRIPTION

This can be installed as a singleton of Yote::ObjProvider and does the actual storage and retreival of Yote objects.

The interaction the developer will have with this may be specifying its intialization arguments.

=head1 CONFIGURATION

The package name is used as an argument to the Yote::ObjProvider package which also takes the configuration parameters for Yote::SQLiteIO.

Yote::ObjProvider::init( datastore => 'Yote::SQLiteIO', db => 'yote_db', uname => 'yote_db_user', pword => 'yote_db_password' );

=head1 PUBLIC METHODS

=over 4

=item client

Return the mongo client object

=item commit_transaction( )

=item count( container_id )

returns the number of items in the given container

=item database( )

Provides a database handle. Used only in testing.

=item disconnect( )

=item ensure_datastore( )

Makes sure that the datastore has the correct table structure set up and in place.

=item fetch( id )

Returns a hash representation of a yote object, hash ref or array ref by id. The values of the object are in an internal storage format and used by Yote::ObjProvider to build the object.

=item first_id( id )

Returns the id of the first object in the system, the YoteRoot.

=item get_id( obj )

Returns the id for the given hash ref, array ref or yote object. If the argument does not have an id assigned, a new id will be assigned.

=item hash_delete( hash_id, key )

Removes the key from the hash given by the id

=item hash_fetch( hash_id, key )

=item hash_has_key( hash_id, key )

=item hash_insert( hash_id, key, value )

=item list_delete( list_id, idx )

=item list_fetch( list_id, idx )

=item list_insert( list_id, val, idx )

Inserts the item into the list with an optional index. If not given, this inserts to the end of the list.

=item max_id( ) 

Returns the max ID in the yote system. Used for testing.

=item new 

=item paginate_hash( hash_id, length, start )

Returns a paginated hash reference

=item paginate_list( list_id, length, start )

Returns a paginated list reference

=item recycle_object( obj_id )

Sets the available for recycle mark on the object entry in the database by object id and removes its data.

=item recycle_objects( start_id, end_id )

Recycles all objects in the range given if they cannot trace back a path to root.

=item start_transaction( )

=item stow( id, class, data )

Stores the object of class class encoded in the internal data format into the data store.

=item stow_all( )

Stows all objects that are marked as dirty. This is called automatically by the application server and need not be explicitly called.


=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
