package Yote::IO::SQLite;

#
# This stows and fetches G objects from a database store and provides object ids.
#

use strict;
use warnings;
no warnings 'uninitialized';
no warnings 'recursion';

use Data::Dumper;
use DBD::SQLite;
use DBI;

use vars qw($VERSION);

$VERSION = '0.035';

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
                     last_updated timestamp,
                     recycled tinyint DEFAULT 0
                      ); CREATE INDEX IF NOT EXISTS rec ON objects( recycled );~,
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
    my( $class ) = $self->_selectrow_array( "SELECT class FROM objects WHERE recycled=0 AND last_updated IS NOT NULL AND id=?",  $id );

    die $self->{DBH}->errstr() if $self->{DBH}->errstr();

    return unless $class;
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
sub _has_path_to_root {
    my( $self, $obj_id, $seen ) = @_;
    return 1 if $obj_id == 1;
    $seen ||= { $obj_id => 1 };
    my $res = $self->_selectall_arrayref( "SELECT obj_id,last_updated FROM field f,objects o WHERE o.id=obj_id AND ref_id=?", $obj_id );
    for my $res ( @$res ) {
	return 1 unless $res->[1];
	my $o_id = $res->[0];
	next if $seen->{ $o_id }++;
	if( $self->_has_path_to_root( $o_id, $seen ) ) {
	    return 1;
	}
    }

    return 0;
} #_has_path_to_root

# returns the max id (mostly used for diagnostics)
sub max_id {
    my $self = shift;
    my( $highd ) = $self->_selectrow_array( "SELECT max(ID) FROM objects" );
    return $highd;
}

sub paginate {
    my( $self, $obj_id, $args ) = @_;

    my $PAG = '';

    if( defined( $args->{ limit } ) ) {
	if( $args->{ skip } ) {
	    $PAG = " LIMIT $args->{ skip },$args->{ limit }";
	} else {
	    $PAG = " LIMIT $args->{ limit }";
	}
    }

    my( $orstr, @params ) = ( '', $obj_id );
    my $search_terms = $args->{ search_terms };
    my $search_fields = $args->{ search_fields };
    if( $search_terms ) {
	if( $search_fields ) {
	    my( @ors );
	    for my $field ( @$search_fields ) {
		for my $term (@$search_terms) {
		    push @ors, " (f.field=? AND f.value LIKE ?) ";
		    push @params, $field, "\%$term\%";
		}
	    }
	    $orstr = @ors > 0 ? " WHERE " . join( ' OR ', @ors )  : '';
	}
	else {
	    $orstr = " AND value IN (".join('',map { '?' } @$search_terms ).")";
	    push @params, map { "\%$_\%" } @$search_terms;
	}
    }

    my $query;
    my( $type ) = $self->_selectrow_array( "SELECT class FROM objects WHERE id=?", $obj_id );

    if( $args->{ sort_fields } ) {
	my $sort_fields = $args->{ sort_fields };
	my $reversed_orders = $args->{ reversed_orders } || [];
	$query = "SELECT bar.field,fi.obj_id,".join(',', map { "GROUP_CONCAT( CASE WHEN fi.field='".$_."' THEN value END )" } @$sort_fields )." FROM field fi, ( SELECT foo.field,foo.ref_id AS ref_id FROM (SELECT field,ref_id FROM field WHERE obj_id=? ) as foo LEFT JOIN field f ON ( f.obj_id=foo.ref_id ) $orstr GROUP BY 1,2) as bar WHERE fi.obj_id=bar.ref_id GROUP BY 1,2 ORDER BY " . join( ',' , map { (3+$_) . ( $reversed_orders->[ $_ ] ? ' DESC' : '' )} (0..$#$sort_fields) ) . $PAG;
    }
    elsif( $search_fields ) {
	$query = "SELECT bar.field,fi.obj_id,bar.value FROM field fi, ( SELECT foo.field,foo.ref_id AS ref_id,foo.value AS value FROM ( SELECT field,ref_id,value FROM field WHERE obj_id=? ) as foo LEFT JOIN field f ON ( f.obj_id=foo.ref_id ) $orstr GROUP BY 1,2) as bar WHERE fi.obj_id=bar.ref_id GROUP BY 1,2 ";
	if( $type eq 'ARRAY' ) {
	    $query .= ' ORDER BY cast( bar.field as int ) ';
	}
	else {
	    $query .= ' ORDER BY bar.field ';
	}
	$query .= ' DESC' if $args->{ reverse };
	$query .= $PAG;
    }
    else {
	$query = "SELECT field,ref_id,value FROM field WHERE obj_id=?";
	if( $type eq 'ARRAY' ) {
	    if( $args->{ sort } ) {
		$query .= ' ORDER BY value ';
	    }
	    else {
		$query .= ' ORDER BY cast( field as int ) ';
	    }
	}
	else {
	    $query .= ' ORDER BY field ';
	}
	$query .= ' DESC' if $args->{ reverse };
	$query .= $PAG;
    }
    my $ret = $self->_selectall_arrayref( $query, @params );
    if( $args->{return_hash} ) {
	if( $type eq 'ARRAY' ) {
	    return { map { ($args->{ skip }+$_) => $ret->[$_][1] || 'v'.$ret->[$_][2] } (0..$#$ret) };
	}
	return { map { $_->[0] => $_->[1] || 'v'.$_->[2] } @$ret };
    }

    return [map { $_->[1] || 'v'.$_->[2] } @$ret ];

} #paginate
#
# Finds objects not connected to the root and recycles them.
# This interface would be broken with the MongDB implementation.
#
sub recycle_objects {
    my( $self, $start_id, $end_id ) = @_;
    $start_id ||= 2;
    $end_id   ||= $self->max_id();

    my $recycled = 0;

    for( my $id=$start_id; $id <= $end_id; $id++ ) {
	my $obj = $self->fetch( $id );
	if( $obj && ( ! $self->_has_path_to_root( $id ) ) ) {
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

sub _stow_now {
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
} #_stow_now

sub stow_all {
    my( $self, $objs ) = @_;
    $self->{QUERIES} = [[[]],[[]]];
    $self->{STOW_LATER} = 1;
    for my $objd ( @$objs ) {
	$self->stow( @$objd );
    }
    $self->_engage_queries();
    $self->{STOW_LATER} = 0;
    $self->{QUERIES} = [[[]],[[]]];
} #stow_all

sub stow {
    my( $self, $id, $class, $data ) = @_;

#    print STDERR "[$$ ".time()."] STOW : $id \n";

    unless( $self->{STOW_LATER} ) {
	return $self->_stow_now( $id, $class, $data );
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

sub _engage_queries {
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
} #_engage_queries

#
# Returns the number of entries in the list of the given id.
#
sub count {
    my( $self, $container_id, $args ) = @_;
    my $count;
    if( $args->{search_fields} && $args->{search_terms} ) {
	my( @ors );
	my( @params ) = $container_id;
	for my $field ( @{$args->{search_fields}} ) {
	    for my $term (@{$args->{search_terms}}) {
		push @ors, " (f.field=? AND f.value LIKE ?) ";
		push @params, $field, "\%$term\%";
	    }
	}
	my $orstr = @ors > 0 ? " WHERE " . join( ' OR ', @ors )  : '';
	( $count ) = $self->_selectrow_array( "SELECT count(*) FROM (SELECT bar.field,fi.obj_id FROM field fi, ( SELECT foo.field,foo.ref_id AS ref_id,foo.value AS value FROM ( SELECT field,ref_id,value FROM field WHERE obj_id=? ) as foo LEFT JOIN field f ON ( f.obj_id=foo.ref_id ) $orstr GROUP BY 1,2) as bar WHERE fi.obj_id=bar.ref_id GROUP BY 1,2) foo", @params );
    } #if count with search
    else {
	( $count ) = $self->_selectrow_array( "SELECT count(*) FROM field WHERE obj_id=?",  $container_id );
    }
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();

    return $count;
} #count

sub list_insert {
    my( $self, $list_id, $val, $idx ) = @_;
    my( $last_idx ) = $self->{DBH}->selectrow_array( "SELECT max( cast( field as int ) ) FROM field WHERE obj_id=?", {}, $list_id );
    if( defined( $idx ) ) {
	if( !defined( $last_idx ) ) {
	    $idx = 0;
	}
	elsif( $idx > $last_idx ) {
	    $idx = $last_idx + 1;
	}
	else {
	    my( $occupied ) = $self->{DBH}->selectrow_array( "SELECT count(*) FROM field WHERE obj_id=? AND field=?", {}, $list_id, $idx );
	    if( $occupied ) {
		$self->{DBH}->do( "UPDATE field SET field=field+1 WHERE obj_id=? AND field >= ?", {}, $list_id, $idx );
	    }
	}
    }
    else {
	if( defined( $last_idx ) ) {
	    $idx = $last_idx + 1;
	}
	else {
	    $idx = 0;
	}
    }

    if( index( $val, 'v' ) == 0 ) {
	$self->_do( "INSERT INTO field (obj_id,field,value) VALUES (?,?,?)", $list_id, $idx, substr( $val, 1 )  );
    } else {
	$self->_do( "INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)", $list_id, $idx, $val );
    }
    return;
} #list_insert

sub hash_delete {
    my( $self, $hash_id, $key ) = @_;
    $self->_do( "DELETE FROM field WHERE obj_id=? AND field=?", $hash_id, $key );
    return;
}


sub hash_insert {
    my( $self, $hash_id, $key, $val ) = @_;
    $self->_do( "DELETE FROM field WHERE obj_id=? AND field=?", $hash_id, $key );
    if( index( $val, 'v' ) == 0 ) {
	$self->_do( "INSERT INTO field (obj_id,field,value) VALUES (?,?,?)", $hash_id, $key, substr( $val, 1 )  );
    } else {
	$self->_do( "INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)", $hash_id, $key, $val );
    }
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();
    return;
} #hash_insert

sub list_delete {
    my( $self, $list_id, $val, $idx ) = @_;
    my( $actual_index ) = $val ?
	$self->_selectrow_array( "SELECT field FROM field WHERE obj_id=? AND ( value=? OR ref_id=? )", $list_id, $val, $val ) :
	$idx;
    $actual_index ||= 0;

    $self->_do( "DELETE FROM field WHERE obj_id=? AND field=?", $list_id, $actual_index );
    $self->_do( "UPDATE field SET field=field-1 WHERE obj_id=? AND field > ?", $list_id, $actual_index );
    return;
}

sub list_fetch {
    my( $self, $list_id, $idx ) = @_;
    my( $val, $ref_id ) = $self->_selectrow_array( "SELECT value, ref_id FROM field WHERE obj_id=? AND field=?", $list_id, $idx );
    return $ref_id || "v$val";
}

sub hash_fetch {
    my( $self, $hash_id, $key ) = @_;
    my( $val, $ref_id ) = $self->_selectrow_array( "SELECT value, ref_id FROM field WHERE obj_id=? AND field=?", $hash_id, $key );
    return $ref_id || "v$val";
}

sub hash_has_key {
    my( $self, $hash_id, $key ) = @_;
    my( $fld ) = $self->_selectrow_array( "SELECT field FROM field WHERE obj_id=? AND field=?", $hash_id, $key );
    return defined( $fld );
}

# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------

sub _connect {
    my $self  = shift;
    my $args  = ref( $_[0] ) ? $_[0] : { @_ };
    my $file  = $args->{ store };
    $self->{DBH} = DBI->connect( "DBI:SQLite:db=$file" );
    $self->{DBH}->{AutoCommit} = 1;
    $self->{file} = $file;
} #_connect

sub _do {
    my( $self, $query, @params ) = @_;
#    print STDERR "Do Query : $query | @params\n";
    my $ret = $self->{DBH}->do( $query, {}, @params );
    die $self->{DBH}->errstr if $self->{DBH}->errstr;
    return $ret;
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

#
# Stores the object to persistance. Object is an array ref in the form id,class,data
#
sub __stow_updates {
    my( $self, $id, $class, $data ) = @_;

    my( @cmds, @cdata );

    push( @cmds, ["UPDATE objects SET last_updated=DateTime('now') WHERE id=?", $id ] );

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

Yote::IO::SQLite - A SQLite persistance engine for Yote.

=head1 DESCRIPTION

This can be installed as a singleton of Yote::ObjProvider and does the actual storage and retreival of Yote objects.

The interaction the developer will have with this may be specifying its intialization arguments.

=head1 CONFIGURATION

The package name is used as an argument to the Yote::ObjProvider package which also takes the configuration parameters for Yote::IO::SQLiteb.

Yote::ObjProvider::init( datastore => 'Yote::IO::SQLite', db => 'yote_db', uname => 'yote_db_user', pword => 'yote_db_password' );

=head1 PUBLIC METHODS

=over 4

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


=item paginate( container_id, args )

Returns a paginated list or hash. Arguments are

=over 4

* search_fields - a list of fields to search for in collections of yote objects
* search_terms - a list of terms to search for
* sort_fields - a list of fields to sort by for collections of yote objects
* reversed_orders - a list of true or false values corresponding to the sort_fields list. A true value means that field is sorted in reverse
* limit - maximum number of entries to return
* skip - skip this many entries before returning the list
* return_hash - return the result as a hashtable rather than as a list
* reverse - return the result in reverse order

=back

=item recycle_object( obj_id )

Sets the available for recycle mark on the object entry in the database by object id and removes its data.

=item recycle_objects( start_id, end_id )

Recycles all objects in the range given if they cannot trace back a path to root.

=item search_list

Returns a paginated search list

=item start_transaction( )

=item stow( id, class, data )

Stores the object of class class encoded in the internal data format into the data store.

=item stow_all( )

Stows all objects that are marked as dirty. This is called automatically by the application server and need not be explicitly called.

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
