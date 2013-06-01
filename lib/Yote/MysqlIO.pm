package Yote::MysqlIO;

#
# This stows and fetches G objects from a database store and provides object ids.
#

use strict;
use warnings;
no warnings 'uninitialized';

use Data::Dumper;
use DBD::MySQL;
use DBI;

use vars qw($VERSION);

$VERSION = '0.03';

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
# Returns the number of entries in the data structure given.
#
sub xpath_count {
    my( $self, $path ) = @_;
    my( @list ) = split( /\//, $path );
    my $next_ref = 1;
    for my $l (@list) {
        next unless $l; #skip blank paths like /foo//bar/  (should just look up foo -> bar
        my( $ref ) = $self->{DBH}->selectrow_array( "SELECT ref_id FROM field WHERE field=? AND obj_id=?", {}, $l, $next_ref );
        print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

        $next_ref = $ref;
        last unless $next_ref;
    } #each path part

    my( $count ) = $self->{DBH}->selectrow_array( "SELECT count(*) FROM field WHERE obj_id=?", {}, $next_ref );
    print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();


    return $count;

} #xpath_count

#
# Returns a single value given the xpath (hash only, and notation is slash separated from root)
# This will always query persistance directly for the value, bypassing objects.
# The use for this is to fetch specific things from potentially very long hashes that you don't want to
#   load in their entirety.
#
sub xpath {
    my( $self, $path ) = @_;
    my( @list ) = split( /\//, $path );
    my $next_ref = 1;
    my $final_val;
    for my $l (@list) {
        next unless defined($l); #skip blank paths like /foo//bar/  (should just look up foo -> bar
	next if $l eq '';
        undef $final_val;
        my( $val, $ref ) = $self->{DBH}->selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?", {}, $l, $next_ref );
        print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

        if( $ref && $val ) {
            my ( $big_val ) = $self->{DBH}->selectrow_array( "SELECT text FROM big_text WHERE obj_id=?", {}, $ref );
            print STDERR Data::Dumper->Dump(["db __LINE__",$self->{DBH}->errstr()]) if $self->{DBH}->errstr();

            $final_val = "v$big_val";
            last;
        } elsif( $ref ) {
            $next_ref = $ref;
            $final_val = $ref;
        } else {
            $final_val = "v$val";
            last;
        }
    } #each path part

    # @TODO: log bad xpath if final_value not defined

    return $final_val;
} #xpath

#
# Deletes a value from the given xpath. /foo/bar/baz. 
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

    my( $class ) = $self->{DBH}->selectrow_array( "SELECT class FROM objects WHERE id=?", {}, $id );
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
# 
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
    my( $self, $path, $paginate_length, $paginate_start, $reverse ) = @_;

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
    my $res = $self->_selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=? ORDER BY field " . ( $reverse ? 'DESC ' : '' ) . " $PAG", $next_ref );
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
	if( $self->has_path_to_root( $new_obj_id, { $obj_id => 1 } ) ) {
	    return $self->path_to_root( $new_obj_id ) . "/$field";
	}
    }

    return;
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

Yote::MysqlIO - A mysql persistance engine for Yote. 

=head1 DESCRIPTION

This is deprecated and has not been further developed. It may be brought up to par with ObjProvider.

This can be installed as a singleton of Yote::ObjProvider and does the actual storage and retreival of Yote objects.

=head1 CONFIGURATION

The package name is used as an argument to the Yote::ObjProvider package which also takes the configuration parameters for Yote::MysqlIO.

Yote::ObjProvider::init( datastore => 'Yote::MysqlIO', db => 'yote_db', uname => 'yote_db_user', pword => 'yote_db_password' );

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

=item first_id( id )

Returns the id of the first object in the system, the YoteRoot.

=item get_id( obj )

Returns the id for the given hash ref, array ref or yote object. If the argument does not have an id assigned, a new id will be assigned.

=item has_path_to_root( obj_id )

Returns true if the object specified by the id can trace a path back to the root yote object.

=item max_id( ) 

Returns the max ID in the yote system. Used for testing.

=item new

=item paginate_xpath( path, start, length )

This method returns a paginated portion of an object that is attached to the xpath given, as internal yote values.

=item paginate_xpath_list( parth, start, length )

This method returns a paginated portion of a list that is attached to the xpath given.

=item path_to_root( object )

Returns the xpath of the given object tracing back a path to the root. This is not guaranteed to be the shortest path to root.

=item paths_to_root( object )

Returns the a list of all valid xpaths of the given object tracing back a path to the root. 

=item recycle_object( obj_id )

Sets the available for recycle mark on the object entry in the database by object id and removes its data.

=item recycle_objects( start_id, end_id )

Recycles all objects in the range given if they cannot trace back a path to root.

=item start_transaction( )

=item stow( id, class, data )

Stores the object of class class encoded in the internal data format into the data store.

=item stow_all( )

Stows all objects that are marked as dirty. This is called automatically by the application server and need not be explicitly called.

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
