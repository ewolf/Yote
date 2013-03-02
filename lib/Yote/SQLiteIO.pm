package Yote::SQLiteIO;

#
# This stows and fetches G objects from a database store and provides object ids.
#

use strict;
use warnings;
no warnings 'uninitialized';
no warnings 'recursion';

use Data::Dumper;
use DBI;

use vars qw($VERSION);

$VERSION = '0.01';

use constant {
    DATA => 2,
    MAX_LENGTH => 1025,
};

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


sub commit_transaction {
    my $self = shift;

#    $self->_do( "COMMIT TRANSACTION" );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();
}

sub database {
    return shift->{DBH};
}

sub disconnect {
    my $self = shift;
    $self->{DBH}->disconnect();
} #disconnect

sub ensure_datastore {
    my $self = shift;
    my %table_definitions = (
        field => q~CREATE TABLE IF NOT EXISTS field (
                   obj_id INTEGER NOT NULL,
                   field varchar(300) DEFAULT NULL,
                   ref_id INTEGER DEFAULT NULL,
                   value varchar(1025) DEFAULT NULL );~,
        objects => q~CREATE TABLE IF NOT EXISTS objects (
                     id INTEGER PRIMARY KEY,
                     class varchar(255) DEFAULT NULL,
                     recycled tinyint DEFAULT 0
                      ); CREATE INDEX IF NOT EXISTS rec ON objects( recycled );~
        );
    my %index_definitions = (
	uniq_idx => q~CREATE INDEX IF NOT EXISTS obj_id ON field(obj_id);~,
	ref_idx => q~CREATE INDEX IF NOT EXISTS ref ON field ( ref_id );~,
        );
    $self->start_transaction();
    for my $value ((values %table_definitions), (values %index_definitions )) {
        $self->_do( $value );
    }
    $self->commit_transaction();
} #ensure_datastore

#
# Returns the first ID that is associated with the root YoteRoot object
#
sub first_id {
    my( $self, $class ) = @_;
    if( $class ) {
	$self->_do( "INSERT OR IGNORE INTO objects (id,class) VALUES (?,?)",  1, $class );
    }
    return 1;
} #first_id

#
# Returns a single object specified by the id. The object is returned as a hash ref with id,class,data.
#
sub fetch {
    my( $self, $id ) = @_;
    my( $class ) = $self->_selectrow_array( "SELECT class FROM objects WHERE recycled=0 AND id=?",  $id );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();


    return undef unless $class;
    my $obj = [$id,$class];
    if( $class  eq 'ARRAY') {
	$obj->[DATA] = [];
	my $res = $self->_selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=?",  $id );
	die $self->{DBH}->errstr() if $self->{DBH}->errstr();
	
	for my $row (@$res) {
	    my( $idx, $ref_id, $value ) = @$row;
	    $obj->[DATA][$idx] = $ref_id || "v$value";
	}
    }
    else {
	$obj->[DATA] = {};
	my $res = $self->_selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=?",  $id );
	die $self->{DBH}->errstr() if $self->{DBH}->errstr();
	
	for my $row (@$res) {
	    my( $field, $ref_id, $value ) = @$row;
	    $obj->[DATA]{$field} = $ref_id || "v$value";
	}
    }
    return $obj;
} #fetch

#
# Given a class, makes new entry in the objects table and returns the generated id
#
sub get_id {
    my( $self, $class ) = @_;

    my( $recycled_id ) = $self->_do( "SELECT id FROM objects WHERE recycled=1 LIMIT 1" );
    if( int($recycled_id) > 0 ) {
	$self->_do( "UPDATE objects SET recycled=0, class=? WHERE id=?", $class, $recycled_id );
	return $recycled_id;
    }
    my $res = $self->_do( "INSERT INTO objects (class) VALUES (?)",  $class );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();

    return $self->{DBH}->last_insert_id(undef,undef,undef,undef);
} #get_id

#
# Returns true if the given object traces back to the root.
#
sub has_path_to_root {
    my( $self, $obj_id, $seen ) = @_;
    return 1 if $obj_id == 1;
    $seen ||= { $obj_id => 1 };
    my $res = $self->_selectall_arrayref( "SELECT obj_id FROM field WHERE ref_id=?", $obj_id );
    for my $o_id (map { $_->[0] } @$res) {
	next if $seen->{ $o_id }++;
	if( $self->has_path_to_root( $o_id, $seen ) ) {
	    return 1;
	}
    }

    return 0;
} #has_path_to_root

# returns the max id (mostly used for diagnostics)
sub max_id {
    my $self = shift;
    my( $highd ) = $self->_selectrow_array( "SELECT max(ID) FROM objects" );
    return $highd;
}

#
# Returns a hash of paginated items that belong to the xpath.
# @TODO - maybe get rid of this, since hash is not a good order dependent thing
sub paginate_xpath {
    my( $self, $path, $paginate_length, $paginate_start ) = @_;

    my( @list ) = _xpath_to_list( $path );
    my $next_ref = 1;
    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar

        my( $val, $ref ) = $self->_selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();


        if( $ref ) {
            $next_ref = $ref;
        }
        else {
	    die "Unable to find xpath location '$path' for pagination";
        }
    } #each path part

    my $PAG = '';
    if( defined( $paginate_start ) ) {
	$PAG = "LIMIT $paginate_start";
	if( $paginate_length ) {
	    $PAG .= ",$paginate_length"
	}
    }    

    my $res = $self->_selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=? ORDER BY field $PAG", $next_ref );
#    return [ map { [ $_->[0], $_->[1] || 'v' . $_->[2] ] } @$res ];
    my %ret;
    for my $row (@$res) {
	$ret{$row->[0]} = $row->[1] || "v$row->[2]";
    }
    return \%ret
} #paginate_xpath

#
# Returns a hash of paginated items that belong to the xpath. Note that this 
# does not preserve indexes ( for example, if the list has two rows, and first index in the database is 3, the list returned is still [ 'val1', 'val2' ]
#   rather than [ undef, undef, undef, 'val1', 'val2' ]
#
sub paginate_xpath_list {
    my( $self, $path, $paginate_length, $paginate_start ) = @_;

    my( @list ) = _xpath_to_list( $path );
    my $next_ref = 1;
    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar

        my( $val, $ref ) = $self->_selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();


        if( $ref ) {
            $next_ref = $ref;
        }
        else {
	    die "Unable to find xpath location '$path' for pagination";
        }
    } #each path part

    my $PAG = '';
    if( defined( $paginate_length ) ) {
	if( $paginate_start ) {
	    $PAG = "LIMIT $paginate_start,$paginate_length";
	} else {
	    $PAG = "LIMIT $paginate_length";
	}
    }    

    my $res = $self->_selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=? ORDER BY cast( field as int ) $PAG", $next_ref );
    my @ret;
    for my $row (@$res) {
	push @ret, $row->[1] || "v$row->[2]";
    }
    return \@ret
} #paginate_xpath_list

#
# Return a path to root that this object has (specified by id), if any.
#
sub path_to_root {
    my( $self, $obj_id ) = @_;
    return '' if $obj_id == 1;
    my $res = $self->_selectall_arrayref( "SELECT obj_id,field FROM field WHERE ref_id=?", $obj_id );
    for my $row (@$res) {
	my( $new_obj_id, $field ) = @$row;
	if( $self->has_path_to_root( $new_obj_id ) ) {
	    return $self->path_to_root( $new_obj_id ) . "/$field";
	}
    }

    return undef;
} #path_to_root

#
# Return all paths to root that this object (specified by id) has, if any.
#
sub paths_to_root {
    my( $self, $obj_id, $seen ) = @_;
    $seen ||= {};
    return [''] if $obj_id == 1;
    my $ret = [];
    my $res = $self->_selectall_arrayref( "SELECT obj_id,field FROM field WHERE ref_id=?", $obj_id );
    for my $row (@$res) {
	my( $new_obj_id, $field ) = @$row;
	if(  ! $seen->{$new_obj_id} && $self->has_path_to_root( $new_obj_id ) ) {
	    $seen->{$new_obj_id} = 1;
	    my $paths = $self->paths_to_root( $new_obj_id, $seen );
	    push @$ret, map { $_. "/$field" } @$paths;
	}
    }
    
    return $ret;
} #paths_to_root

#
# Finds objects not connected to the root and recycles them.
# This interface would be broken with the MongDB implementation.
#
sub recycle_objects {
    my( $self, $start_id, $end_id ) = @_;
    $start_id ||= 2;
    $end_id   ||= $self->max_id();

    my $recycled;
    
    for( my $id=$start_id; $id <= $end_id; $id++ ) {
	my $obj = $self->fetch( $id );
	if( $obj && ( ! $self->has_path_to_root( $id ) ) ) {
	    $self->recycle_object( $id );
	    ++$recycled;
	}
    }
    #print STDERR "RECYCLED $recycled objects\n";
    return $recycled;
} #recycle_objects

sub recycle_object {
    my( $self, $obj_id ) = @_;
    $self->_do( "DELETE FROM field WHERE obj_id=? or ref_id=?", $obj_id, $obj_id );
    $self->_do( "UPDATE objects SET class=NULL,recycled=1 WHERE id=?", $obj_id );
}

sub start_transaction {
    my $self = shift;
#    $self->_do( "BEGIN IMMEDIATE TRANSACTION" );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();
}

sub stow_now {
    my( $self, $id, $class, $data ) = @_;
    my(  $updates, $udata ) = $self->__stow_updates( $id, $class, $data );    
    for my $upd (@$updates) {
	$self->_do( @$upd );
	die $self->{DBH}->errstr() if $self->{DBH}->errstr();
    }
    my $first_data = shift @$udata;
    if( $first_data ) {
	$self->_do( qq~INSERT INTO field
                       SELECT ? AS obj_id, ? AS field, ? as ref_id, ? as value ~.
		    join( ' ', map { ' UNION SELECT ?, ?, ?, ? ' } @$udata ),
		    map { @$_ } $first_data, @$udata );
    }
} #stow_now

sub stow_all {
    my( $self, $objs ) = @_;
    $self->{QUERIES} = [[[]],[[]]];
    $self->{STOW_LATER} = 1;
    for my $objd ( @$objs ) {
	$self->stow( @$objd );
    }
    $self->engage_queries();
    $self->{STOW_LATER} = 0;
    $self->{QUERIES} = [[[]],[[]]];
} #stow_all

sub stow {
    my( $self, $id, $class, $data ) = @_;

    unless( $self->{STOW_LATER} ) {
	return $self->stow_now( $id, $class, $data );
    }
    my( $updates, $udata ) = $self->__stow_updates( $id, $class, $data );
    my $ups = $self->{QUERIES}[0];
    my $uds = $self->{QUERIES}[1];
    my $llist = $ups->[$#$ups];
    if( scalar( @$llist ) > 50 ) {
	$llist = [];
	push( @$ups, $llist );
	push( @$uds, [] );
    }
    my $uus = $uds->[$#$uds];
    push( @$llist, @$updates );
    push( @$uus,   @$udata   );
} #stow

sub engage_queries {
    my $self = shift;
    my( $upds, $uds ) = @{ $self->{QUERIES} };
    for( my $i=0; $i < scalar( @$upds ); $i++ ) {
	my $updates = $upds->[ $i ];
	my $udata   = $uds->[ $i ];
	for my $upd (@$updates) {
	    $self->_do( @$upd );
	    die $self->{DBH}->errstr() if $self->{DBH}->errstr();
	}
	my $first_data = shift @$udata;
	if( $first_data ) {
	    $self->_do( qq~INSERT INTO field
                       SELECT ? AS obj_id, ? AS field, ? as ref_id, ? as value ~.
			join( ' ', map { ' UNION SELECT ?, ?, ?, ? ' } @$udata ),
			map { @$_ } $first_data, @$udata );
	}
    }
} #engage_queries


#
# Returns a single value given the xpath (notation is slash separated from root)
# This will always query persistance directly for the value, bypassing objects.
# The use for this is to fetch specific things from potentially very long hashes that you don't want to
#   load in their entirety.
#
sub xpath {
    my( $self, $path ) = @_;
    my( @list ) = _xpath_to_list( $path );
    my $next_ref = 1;
    my $final_val;
    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar
        undef $final_val;
        my( $val, $ref ) = $self->_selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();

        if( $ref ) {
            $next_ref = $ref;
            $final_val = $ref;
        }
	else {
            $final_val = "v$val";
            last;
        }
    } #each path part

    # @TODO: log bad xpath if final_value not defined

    return $final_val;
} #xpath

#
# Returns the number of entries in the data structure given.
#
sub xpath_count {
    my( $self, $path ) = @_;
    my( @list ) = _xpath_to_list( $path );
    my $next_ref = 1;
    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar

        my( $ref ) = $self->_selectrow_array( "SELECT ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();

        $next_ref = $ref;
        last unless $next_ref;
    } #each path part

    my( $count ) = $self->_selectrow_array( "SELECT count(*) FROM field WHERE obj_id=?",  $next_ref );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();


    return $count;

} #xpath_count


#
# Inserts a value into the given xpath. /foo/bar/baz. Overwrites old value if it exists. Appends if it is a list.
#
sub xpath_delete {
    my( $self, $path ) = @_;

    my( @list ) = _xpath_to_list( $path );
    my $field = pop @list;
    my $next_ref = 1;
    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar

        my( $val, $ref ) = $self->_selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();

        if( $ref ) {
            $next_ref = $ref;
        }
        else {
	    die "Unable to find xpath location '$path' for delete";
        }
    } #each path part

    #find the object type to see if this is an array to append to, or a hash to insert to
    $self->_do( "DELETE FROM field WHERE obj_id = ? AND field=?", $next_ref, $field );

} #xpath_delete

#
# Inserts a value into the given xpath. /foo/bar/baz. Overwrites old value if it exists.
#
sub xpath_insert {
    my( $self, $path, $item_to_insert ) = @_;

    my( @list ) = _xpath_to_list( $path );
    my $field = pop @list;
    my $next_ref = 1;
    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar

        my( $val, $ref ) = $self->_selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();

        if( $ref ) {
            $next_ref = $ref;
        }
        else {
	    die "Unable to find xpath location '$path' for insert";
        }
    } #each path part

    $self->_do( "DELETE FROM field WHERE obj_id = ? AND field=?", $next_ref, $field );

    if( index( $item_to_insert, 'v' ) == 0 ) {
	$self->_do( "INSERT INTO field (obj_id,field,value) VALUES (?,?,?)", $next_ref, $field, substr( $item_to_insert, 1)  );
    } else {
	$self->_do( "INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)", $next_ref, $field, $item_to_insert );
    }

} #xpath_insert

#
# Appends a value into the list located at the given xpath.
#
sub xpath_list_insert {
    my( $self, $path, $item_to_insert ) = @_;

    my( @list ) = _xpath_to_list( $path );
    my $next_ref = 1;
    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar

        my( $val, $ref ) = $self->_selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();

        if( $ref ) {
            $next_ref = $ref;
        }
        else {
	    die "Unable to find xpath location '$path' for insert";
        }
    } #each path part

    my( $field ) = $self->_selectrow_array( "SELECT max(field) + 1 FROM field WHERE obj_id=?", $next_ref );

   if( index( $item_to_insert, 'v' ) == 0 ) {
	$self->_do( "INSERT INTO field (obj_id,field,value) VALUES (?,?,?)", $next_ref, $field, substr( $item_to_insert, 1)  );
    } else {
	$self->_do( "INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)", $next_ref, $field, $item_to_insert );
    }

} #xpath_list_insert


# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

sub _connect {
    my $self  = shift;
    my $args  = ref( $_[0] ) ? $_[0] : { @_ };
    my $file  = $args->{sqlitefile} || $self->{args}{sqlitefile} || '/usr/local/yote/data/SQLite.yote.db';
    $self->{DBH} = DBI->connect( "DBI:SQLite:db=$file" );
    $self->{DBH}->{AutoCommit} = 1;
    $self->{file} = $file;
} #_connect

sub _do {
    my( $self, $query, @params ) = @_;
#    print STDERR "Do Query : $query @params\n";
    return $self->{DBH}->do( $query, {}, @params );
} #_do

sub _selectrow_array {
    my( $self, $query, @params ) = @_;
#    print STDERR "Do Query : $query @params\n";
    return $self->{DBH}->selectrow_array( $query, {}, @params );
} #_selectrow_array

sub _selectall_arrayref {
    my( $self, $query, @params ) = @_;
#    print STDERR "Do Query : $query @params\n";
    return $self->{DBH}->selectall_arrayref( $query, {}, @params );
} #_selectall_arrayref


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

#
# Stores the object to persistance. Object is an array ref in the form id,class,data
#
sub __stow_updates {
    my( $self, $id, $class, $data ) = @_;

    my( @cmds, @cdata );

    if( $class eq 'ARRAY') {
	push( @cmds, ["DELETE FROM field WHERE obj_id=?",  $id ] );


	for my $i (0..$#$data) {
	    next unless defined $data->[$i];
	    my $val = $data->[$i];
	    if( index( $val, 'v' ) == 0 ) {
#		    push( @cmds, ["INSERT INTO field (obj_id,field,value) VALUES (?,?,?)",  $id, $i, substr($val,1) ] );
		push( @cdata, [$id, $i, '', substr($val,1) ] );
	    } else {
#                    push( @cmds, ["INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)",  $id, $i, $val ] );
		push( @cdata, [$id, $i, $val, '' ] );
	    }
	}
    }
    else {
	push( @cmds, ["DELETE FROM field WHERE obj_id=?",  $id ] );
	for my $key (keys %$data) {
	    my $val = $data->{$key};
	    if( index( $val, 'v' ) == 0 ) {
#		    push( @cmds, ["INSERT INTO field (obj_id,field,value) VALUES (?,?,?)",  $id, $key, substr($val,1) ] );
		push( @cdata, [$id, $key, '', substr($val,1) ] );
	    }
	    else {
#                    push( @cmds, ["INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)",  $id, $key, $val ] );
		push( @cdata, [$id, $key, $val, '' ] );
	    }
	} #each key
    }
    return \@cmds,\@cdata;
} # __stow_updates


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
