package Yote::MongoIO;

#
# This stows and fetches G objects from a database store and provides object ids.
#

use strict;
use warnings;
no warnings 'uninitialized';
no warnings 'recursion';
use feature ':5.10';

use Data::Dumper;
use MongoDB;

use vars qw($VERSION);

$VERSION = '0.01';

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
    return undef unless $data;
    return [ $id, $data->{ c }, $data->{d} ];
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
sub has_path_to_root {
    my( $self, $obj_id, $seen ) = @_;
    return 1 if $obj_id eq $self->first_id();
    $seen ||= { $obj_id => 1 };

    my $curs = $self->{ OBJS }->find( { r => $obj_id } );
    while( my $obj = $curs->next ) {
	my $o_id = $obj->{ _id }{ value };
	next if $seen->{ $o_id }++;
	if( $self->has_path_to_root( $o_id, $seen ) ) {
	    return 1;
	}
    }
    return 0;
} #has_path_to_root

#
# Returns a hash of paginated items that belong to the xpath. The xpath must end in a hash.
# 
sub paginate_xpath {
    my( $self, $path, $paginate_start, $paginate_length ) = @_;

    my $obj_id = $self->xpath( $path );
    die "Unable to find xpath location '$path' for pagination" unless $obj_id;

    my $obj = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $obj_id ) } );

    die "Unable to find xpath location '$path' for pagination" unless $obj;

    my $result_data = $obj->{ d };

    if( $obj->{ c } eq 'ARRAY' ) {
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
		    return [];
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
	return $result_data;
    }
} #paginate_xpath

#
# Returns a hash of paginated items that belong to the xpath. Note that this 
# does not preserve indexes ( for example, if the list has two rows, and first index in the database is 3, the list returned is still [ 'val1', 'val2' ]
#   rather than [ undef, undef, undef, 'val1', 'val2' ]
#
sub paginate_xpath_list {
    my( $self, $path, $paginate_length, $paginate_start ) = @_;
    my $obj_id = $self->xpath( $path );
    die "Unable to find xpath location '$path' for pagination" unless $obj_id;

    my $obj = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $obj_id ) } );
    die "Unable to find xpath location '$path' for pagination" unless $obj;
    die "xpath list pagination must be called for array" if $obj->{ c } ne 'ARRAY';

    my $result_data = $obj->{ d };

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
} #paginate_xpath_list

#
# Return a path to root that this object has (specified by id), if any.
#
sub path_to_root {
    my( $self, $obj_id ) = @_;
    return '' if $obj_id eq $self->first_id();

    my $curs = $self->{ OBJS }->find( { r => $obj_id } );

    while( my $obj = $curs->next ) {
	my $d = $obj->{ d };
	my $field;
	if( $obj->{ c } eq 'ARRAY' ) {
	    for( my $f=0; $f < @$d; $f++ ) {
		$field = $f;
		last if $d->[ $field ] eq $obj_id;
	    }
	} 
	else {
	    for my $f ( keys %$d ) {
		$field = $f;
		last if $d->{$field} eq $obj_id;
	    }
	}
	my $new_obj_id = $obj->{ _id }{ value };
	if( $self->has_path_to_root( $new_obj_id ) ) {
	    return $self->path_to_root( $new_obj_id ) . "/$field";
	}
    } #each doc

    return undef;
} #path_to_root

#
# Return all paths to root that this object (specified by id) has, if any.
#
sub paths_to_root {
    my( $self, $obj_id, $seen ) = @_;
    $seen ||= {};
    return [''] if $obj_id eq $self->first_id();
    my $ret = [];

    my $curs = $self->{ OBJS }->find( { r => $obj_id } );

    while( my $obj = $curs->next ) {
	my $d = $obj->{ d };
	my $field;
	if( $obj->{ c } eq 'ARRAY' ) {
	    for( $field=0; $field < @$d; $field++ ) {
		last if $d->[ $field ] eq $obj_id;
	    }
	} 
	else {
	    for $field ( keys %$d ) {
		last if $d->{$field} eq $obj_id;
	    }
	}
	my $new_obj_id = $obj->{ _id }{ value };
	if( ! $seen->{ $new_obj_id } && $self->has_path_to_root( $new_obj_id ) ) {
	    $seen->{ $new_obj_id } = 1;
	    my $paths = $self->paths_to_root( $new_obj_id, $seen );
	    push @$ret, map { "$_/$field" } @$paths;
	}
    } #each doc
    
    return $ret;
} #paths_to_root


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
	unless( $self->has_path_to_root( $id ) ) {
	    $self->recycle_object( $id );
	    $rec_count++;
	}
    }
    return $rec_count;
} #recycle_object

sub start_transaction {}

sub reset_queries {}

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
} #stow

#
# Returns a single value given the xpath (notation is slash separated from root)
# This will always query persistance directly for the value, bypassing objects.
# The use for this is to fetch specific things from potentially very long hashes that you don't want to
#   load in their entirety.
#
sub xpath {
    my( $self, $path ) = @_;
    my( @list ) = _xpath_to_list( $path );
    my $final_field = pop @list;
    my $next_ref = $self->first_id();

    my $odata = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $next_ref ) } );

    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar

	if( $odata->{c} eq 'ARRAY' ) {
	    if( $l > 0 || $l eq '0' ) {
		$next_ref = $odata->{ d }[ $l ];		
	    } 
	}
	else {
	    $next_ref = $odata->{ d }{ $l };
	}
	return undef unless defined( $next_ref );
	return undef if index( $next_ref, 'v' ) == 0;
	$odata = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $next_ref ) } );
    } #each path part

    return undef unless $odata;

    # @TODO: log bad xpath if final_value not defined
    if( $odata->{c} eq 'ARRAY' ) {
	if( $final_field > 0 || $final_field eq '0' ) {
	    return $odata->{ d }[ $final_field ];		
	} 
    }
    else {
	return $odata->{ d }{ $final_field };
    }

    return undef;
} #xpath

#
# Returns the number of entries in the data structure given.
#
sub xpath_count {
    my( $self, $path ) = @_;

    my $obj_id = $self->xpath( $path );
    return undef unless $obj_id;

    my $odata = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $obj_id ) } );
    return undef unless $odata;

    # @TODO: log bad xpath if final_value not defined
    if( $odata->{c} eq 'ARRAY' ) {
	return scalar( @{ $odata->{ d } } );
    }
    return scalar( keys %{$odata->{ d }} );
} #xpath_count

#
# Deletes a value into the given xpath. /foo/bar/baz. 
#
sub xpath_delete {
    my( $self, $path ) = @_;

    my( @list ) = _xpath_to_list( $path );
    my $del_field = pop @list;

    my $o_id = $self->xpath( join( '/', @list ) );
    die "Unable to find xpath location '$path' for delete" unless $o_id;

    my $obj = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $o_id ) } );
    die "Unable to find xpath location '$path' for delete" unless $obj;

    if( $obj->{ c } eq 'ARRAY' ) {
	if( $del_field > 0 || $del_field eq '0' ) {
	    if( $obj->{ d }[ $del_field ] ) {
		# this is where ya need to update the document
		$self->{ OBJS }->update( { _id => $obj->{ _id } }, { '$unset' => { "d.$del_field" => 1 } } );
		$self->{ OBJS }->update( { _id => $obj->{ _id } }, { '$pull' =>  { "d" => undef } } );
		return 1;
	    }
	}
	return 0;
    }
    elsif( $obj->{ d }{ $del_field } ) {
	$self->{ OBJS }->update( { _id => $obj->{ _id } }, { '$unset' => { "d.$del_field" => 1 } } );
	return 1;
    }
    return 0;
} #xpath_delete

#
# Inserts a value into the given xpath. /foo/bar/baz. Overwrites old value if it exists.
#
sub xpath_insert {
    my( $self, $path, $item_to_insert ) = @_;

    my( @list ) = _xpath_to_list( $path );
    my $field = pop @list;

    my $obj_id = $self->xpath( join( '/', @list ) );
    die "Unable to find xpath location '$path' for insert" unless $obj_id;

    my $obj = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $obj_id ) } );
    die "Unable to find xpath location '$path' for insert" unless $obj;
    die "xpath_insert must be called for hash" if $obj->{ c } ne 'HASH' and $field == 0 and $field != '0';

    $self->{ OBJS }->update( { _id => MongoDB::OID->new( value => $obj->{ _id }{ value } ) }, 
			     { '$set' => { "d.$field" => $item_to_insert } } );

} #xpath_insert

#
# Appends a value into the list located at the given xpath.
#
sub xpath_list_insert {
    my( $self, $path, $item_to_insert ) = @_;

    my $obj_id = $self->xpath( $path );
    die "xpath_list_insert must be called for array" unless $obj_id;
    my $obj = $self->{ OBJS }->find_one( { _id => MongoDB::OID->new( value => $obj_id ) } );
    die "xpath_list_insert must be called for array" unless $obj;
    die "xpath_list_insert must be called for array" if $obj->{ c } ne 'ARRAY';

    $self->{ OBJS }->update( { _id => MongoDB::OID->new( value => $obj->{ _id }{ value } ) }, 
			     { '$push' => { "d" => $item_to_insert } } );
} #xpath_list_insert


# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

sub _connect {
    my $self  = shift;
    my $args  = ref( $_[0] ) ? $_[0] : { @_ };
    $self->{MONGO_CLIENT} = MongoDB::MongoClient->new(
	host=> $args->{ datahost },
	port=> $args->{ dataport }
	);
    $self->{DB} = $self->{MONGO_CLIENT}->get_database( $args->{ databasename } || 'yote' );
} #_connect

sub _xpath_to_list {
    my $path = shift;
    my( @path ) = split( //, $path );
    my( $working, $escaped, @res ) = '';
    for my $ch (@path) {
	if( $ch eq '/' && ! $escaped ) {
	    push( @res, $working );
	    $working = '';
	    $escaped = 0;
	} 
	elsif( $ch eq '\\' ) {
	    $escaped = 1;
	}
	else {
	    $working .= $ch;
	}
    }
    push( @res, $working ) if defined( $working );
    return @res;
} #_xpath_to_list
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

=item commit_transaction( )

=item database( )

Provides a database handle. Used only in testing.

=item disconnect( )

=item ensure_datastore( )

Makes sure that the datastore has the correct table structure set up and in place.

=item fetch( id )

Returns a hash representation of a yote object, hash ref or array ref by id. The values of the object are in an internal storage format and used by Yote::ObjProvider to build the object.

=item get_id( obj )

Returns the id for the given hash ref, array ref or yote object. If the argument does not have an id assigned, a new id will be assigned.

=item has_path_to_root( obj_id )

Returns true if the object specified by the id can trace a path back to the root yote object.

=item max_id( ) 

Returns the max ID in the yote system. Used for testing.

=item paginate_xpath( path, start, length )

This method returns a paginated portion of an object that is attached to the xpath given, as internal yote values.

=item paginate_xpath_list( parth, start, length )

This method returns a paginated portion of a list that is attached to the xpath given.

=item path_to_root( object )

Returns the xpath of the given object tracing back a path to the root. This is not guaranteed to be the shortest path to root.

=item recycle_object( obj_id )

Sets the available for recycle mark on the object entry in the database by object id and removes its data.

=item start_transaction( )

=item stow( id, class, data )

Stores the object of class class encoded in the internal data format into the data store.

=item xpath( path )

Given a path designator, returns the object data at the end of it, starting in the root. The notation is /foo/bar/baz where foo, bar and baz are field names. 

=item xpath_count( path )

Given a path designator, returns the number of fields of the object at the end of it, starting in the root. The notation is /foo/bar/baz where foo, bar and baz are field names. This is useful for counting how many things are in a list.

=item xpath_delete( path )

Deletes the entry specified by the path.

=item xpath_insert( path, item )

Inserts the item at the given xpath, overwriting anything that had existed previously.

=item xpath_list_insert( path, item )

Appends the item to the list located at the given xpath.


=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
