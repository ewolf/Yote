package Yote::IO::Mysql;

#
# This stows and fetches G objects from a database store and provides object ids.
#

use strict;
use warnings;
no warnings 'uninitialized';

use Data::Dumper;
use DBI;

use vars qw($VERSION);

$VERSION = '0.034';

use constant {
    DATA => 2,
    MAX_LENGTH => 1025,
};

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

sub _connect {
    my $self  = shift;
    my $args  = ref( $_[0] ) ? $_[0] : { @_ };
    my $db    = $args->{ store };
    my $uname = $args->{ user };
    my $pword = $args->{ password };
    my $host  = $args->{ host };
    my $port  = $args->{ engine_port };
    my $connect = "DBI:mysql:$db";
    $connect .= ":host=$host" if $host;
    $connect .= ":port=$port" if $port;
    $self->{DBH} = DBI->connect( $connect, $uname, $pword );
} #_connect

sub database {
    return shift->{DBH};
}

sub disconnect {
    my $self = shift;
    $self->{DBH}->disconnect();
} #disconnect

sub ensure_datastore {
    my $self = shift;

    my %definitions = (
        field => q~CREATE TABLE `field` (
                   `obj_id` int(10) unsigned NOT NULL,
                   `field` varchar(300) DEFAULT NULL,
                   `ref_id` int(10) unsigned DEFAULT NULL,
                   `value` varchar(1025) DEFAULT NULL,
                   KEY `obj_id` (`obj_id`),
                   KEY `ref_id` (`ref_id`)
               ) ENGINE=InnoDB DEFAULT CHARSET=latin1~,
        big_text => q~CREATE TABLE `big_text` (
                       `obj_id` int(10) unsigned NOT NULL,
                       `text` text,
                       PRIMARY KEY (`obj_id`)
                      ) ENGINE=InnoDB CHARSET=latin1~,
        objects => q~CREATE TABLE `objects` (
                     `id` int(11) NOT NULL AUTO_INCREMENT,
                     `class` varchar(255) DEFAULT NULL,
                     `last_updated` datetime,
                     `recycled` tinyint DEFAULT 0,
                      PRIMARY KEY (`id`)
                      ) ENGINE=InnoDB DEFAULT CHARSET=latin1~
        );
    $self->{DBH}->do( "START TRANSACTION" );
    my $today = $self->{DBH}->selectrow_array( "SELECT now()" );
    $today =~ s/[^0-9]+//g;
    for my $table (keys %definitions ) {
        my( $t ) = $self->{DBH}->selectrow_array( "SHOW TABLES LIKE '$table'" );
        if( $t ) {
            my $existing_def = $self->{DBH}->selectall_arrayref( "SHOW CREATE TABLE $table" );
            my $current_def = $definitions{$table};

            #normalize whitespace for comparison
            $current_def =~ s/[\s\n\r]+/ /gs;
            $existing_def =~ s/[\s\n\r]+/ /gs;

            if( lc( $current_def ) eq lc( $existing_def ) ) {
                print STDERR "Table '$table' exists and is the same version\n";
            } else {
                my $backup = "${table}_$today";
                print STDERR "Table definition mismatch for $table. Rename old table '$table' to '$backup' and creating new one.\n";
                $self->{DBH}->do("RENAME TABLE $table TO $backup\n");
                $self->{DBH}->do( $definitions{$table} );
            }
        } else {
            print STDERR "Creating table $table\n";
            $self->{DBH}->do( $definitions{$table} );
        }
    }
    $self->{DBH}->do( "COMMIT" );
} #ensure_datastore


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
    my( $last_idx ) = $self->{DBH}->selectrow_array( "SELECT max( cast( field as unsigned ) ) FROM field WHERE obj_id=?", {}, $list_id );
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

# return single item from a list
sub list_fetch {
    my( $self, $list_id, $idx ) = @_;
    my( $val, $ref_id ) = $self->_selectrow_array( "SELECT value, ref_id FROM field WHERE obj_id=? AND field=?", $list_id, $idx );
    return $ref_id || "v$val";
} 

# return single item from a hash
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
sub _do {
    my( $self, $query, @args ) = @_;
    return $self->{DBH}->do( $query, {}, @args );
}

sub _selectrow_array {
    my( $self, $query, @args ) = @_;
    return $self->{DBH}->selectrow_array( $query, {}, @args );
}

sub _selectall_arrayref {
    my( $self, $query, @args ) = @_;
    return $self->{DBH}->selectall_arrayref( $query, {}, @args );
}


#
# Returns the first ID that is associated with the root YoteRoot object
#
sub first_id {
    my( $self, $class ) = @_;
    if( $class ) {
	$self->_do( "INSERT IGNORE INTO objects (id,class) VALUES (?,?)",  1, $class );
    }
    return 1;
} #first_id

#
# Returns a single object specified by the id. The object is returned as a hash ref with id,class,data.
#
sub fetch {
    my( $self, $id ) = @_;

    my( $class ) = $self->{DBH}->selectrow_array( "SELECT class FROM objects WHERE recycled=0 AND last_updated IS NOT NULL AND id=?", {}, $id );
    print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

    return unless $class;
    my $obj = [$id,$class];
    if( $class eq 'ARRAY') {
	$obj->[DATA] = [];
	my $res = $self->{DBH}->selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=?", {}, $id );
	print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

	for my $row (@$res) {
	    my( $idx, $ref_id, $value ) = @$row;
	    if( $ref_id && $value ) {
		my( $val ) = $self->{DBH}->selectrow_array( "SELECT text FROM big_text WHERE obj_id=?", {}, $ref_id );
		print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

		( $obj->[DATA][$idx] ) = "v$val";
	    } else {
		$obj->[DATA][$idx] = $ref_id || "v$value";
	    }
	}
    }
    else {
	$obj->[DATA] = {};
	my $res = $self->{DBH}->selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=?", {}, $id );
	print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

	for my $row (@$res) {
	    my( $field, $ref_id, $value ) = @$row;
	    if( $ref_id && $value ) {
		my( $val ) = $self->{DBH}->selectrow_array( "SELECT text FROM big_text WHERE obj_id=?", {}, $ref_id );
		print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

		( $obj->[DATA]{$field} ) = "v$val";
	    } else {
		$obj->[DATA]{$field} = $ref_id || "v$value";
	    }
	}
    }
    return $obj;
} #fetch

#
# Given a class, makes new entry in the objects table and returns the generated id
#
sub get_id {
    my( $self, $class ) = @_;

    my $res = $self->{DBH}->do( "INSERT INTO objects (class) VALUES (?)", {}, $class );
    print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

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

sub commit_transaction {
    my $self = shift;

    $self->_do( "COMMIT" );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();
}

sub start_transaction {
    my $self = shift;
    $self->_do( "BEGIN" );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();
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

    my( $type ) = $self->_selectrow_array( "SELECT class FROM objects WHERE id=?", $obj_id );
    my $query;
    if( $args->{ sort_fields } ) {
	my $sort_fields = $args->{ sort_fields };
	my $reversed_orders = $args->{ reversed_orders } || [];
	$query = "SELECT bar.field,fi.obj_id,".join(',', map { "GROUP_CONCAT( CASE WHEN fi.field='".$_."' THEN value END )" } @$sort_fields )." FROM field fi, ( SELECT foo.field,foo.ref_id AS ref_id FROM (SELECT field,ref_id FROM field WHERE obj_id=? ) as foo LEFT JOIN field f ON ( f.obj_id=foo.ref_id ) $orstr GROUP BY 1,2) as bar WHERE fi.obj_id=bar.ref_id GROUP BY 1,2 ORDER BY " . join( ',' , map { (3+$_) . ( $reversed_orders->[ $_ ] ? ' DESC' : '' )} (0..$#$sort_fields) ) . $PAG;
    }
    elsif( $search_fields ) {

	$query = "SELECT bar.field,fi.obj_id,bar.value FROM field fi, ( SELECT foo.field,foo.ref_id AS ref_id,foo.value AS value FROM ( SELECT field,ref_id,value FROM field WHERE obj_id=? ) as foo LEFT JOIN field f ON ( f.obj_id=foo.ref_id ) $orstr GROUP BY 1,2) as bar WHERE fi.obj_id=bar.ref_id GROUP BY 1,2 ";
	if( $type eq 'ARRAY' ) {
	    $query .= ' ORDER BY cast( bar.field as unsigned ) ';
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
		$query .= ' ORDER BY cast( field as unsigned ) ';
	    }
	}
	else {
	    $query .= ' ORDER BY field ';
	}
	$query .= ' DESC' if $args->{ reverse };
	$query .= $PAG;	
    }
    my $ret = $self->_selectall_arrayref( $query, @params );
#    print STDERR Data::Dumper->Dump([$query,\@params,$ret]);
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

    my $recycled;
    
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

#
# Stores the object to persistance. Object is an array ref in the form id,class,data
#
sub stow {
    my( $self, $id, $class, $data ) = @_;

    $self->{DBH}->do("UPDATE objects SET last_updated=now() WHERE id=?", {}, $id );
    if( $class eq 'ARRAY') {
	$self->{DBH}->do( "DELETE FROM field WHERE obj_id=?", {}, $id );
	print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

	for my $i (0..$#$data) {
	    my $val = $data->[$i];
	    if( index( $val, 'v' ) == 0 ) {
		if( length( $val ) > MAX_LENGTH ) {
		    my $big_id = $self->get_id( "BIGTEXT" );
		    $self->{DBH}->do( "INSERT INTO field (obj_id,field,ref_id,value) VALUES (?,?,?,'V')", {}, $id, $i, $big_id );
		    print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

		    $self->{DBH}->do( "INSERT INTO big_text (obj_id,text) VALUES (?,?)", {}, $big_id, substr($val,1) );
		    print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

		} else {
		    $self->{DBH}->do( "INSERT INTO field (obj_id,field,value) VALUES (?,?,?)", {}, $id, $i, substr($val,1) );
		    print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

		}
	    } else {
		$self->{DBH}->do( "INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)", {}, $id, $i, $val );
		print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

	    }
	}
    }
    else {
	$self->{DBH}->do( "DELETE FROM field WHERE obj_id=?", {}, $id );
	print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();
	for my $key (keys %$data) {
	    my $val = $data->{$key};
	    if( index( $val, 'v' ) == 0 ) {
		if( length( $val ) > MAX_LENGTH ) {
		    my $big_id = $self->get_id( "BIGTEXT" );
		    $self->{DBH}->do( "INSERT INTO field (obj_id,field,ref_id,value) VALUES (?,?,?,'V')", {}, $id, $key, $big_id );
		    print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

		    $self->{DBH}->do( "INSERT INTO big_text (obj_id,text) VALUES (?,?)", {}, $big_id, substr($val,1) );
		    print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

		} else {
		    $self->{DBH}->do( "INSERT INTO field (obj_id,field,value) VALUES (?,?,?)", {}, $id, $key, substr($val,1) );
		    print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

		}
	    }
	    else {
		$self->{DBH}->do( "INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)", {}, $id, $key, $val );
		print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

	    }
	} #each key
    }
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

1;
__END__

=head1 NAME

Yote::IO::Mysql - A mysql persistance engine for Yote. 

=head1 DESCRIPTION

Persistance engine that uses mysql as a store.

=head1 CONFIGURATION

The package name is used as an argument to the Yote::ObjProvider package which also takes the configuration parameters for Yote::IO::Mysql.

Yote::ObjProvider::init( datastore => 'Yote::IO::Mysql', db => 'yote_db', uname => 'yote_db_user', pword => 'yote_db_password' );

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
