package Yote::SQLiteIO;

#
# This stows and fetches G objects from a database store and provides object ids.
#

use strict;
use feature ':5.10';

use Data::Dumper;
use DBI;

use vars qw($VERSION);

$VERSION = '0.01';

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
    $self->connect( $args );
    return $self;
} #new

sub database {
    return shift->{DBH};
}

sub do {
    my( $self, $query, @params ) = @_;
#    print STDERR "Do Query : $query\n";
    return $self->{DBH}->do( $query, {}, @params );
}

sub selectrow_array {
    my( $self, $query, @params ) = @_;
#    print STDERR "Do Query : $query @params\n";
    return $self->{DBH}->selectrow_array( $query, {}, @params );
}

sub selectall_arrayref {
    my( $self, $query, @params ) = @_;
#    print STDERR "Do Query : $query\n";
    return $self->{DBH}->selectall_arrayref( $query, {}, @params );
}

sub connect {
    my $self  = shift;
    my $args  = ref( $_[0] ) ? $_[0] : { @_ };
    my $file  = $args->{sqlitefile} || $self->{args}{sqlitefile} || '/usr/local/yote/data/SQLite.yote.db';
    $self->{DBH} = DBI->connect( "DBI:SQLite:db=$file" );
    $self->{DBH}->{AutoCommit} = 1;
    $self->{file} = $file;
} #connect


sub disconnect {
    my $self = shift;
    $self->{DBH}->disconnect();
} #disconnect


sub start_transaction {
    my $self = shift;
#    $self->do( "BEGIN IMMEDIATE TRANSACTION" );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();
}

sub commit_transaction {
    my $self = shift;

#    $self->do( "COMMIT TRANSACTION" );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();
}


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
	uniq_idx => q~CREATE INDEX IF NOT EXISTS obj_id_field ON field(obj_id,field);~,
	ref_idx => q~CREATE INDEX IF NOT EXISTS ref ON field ( ref_id );~,
        );
    $self->start_transaction();
    for my $value ((values %table_definitions), (values %index_definitions )) {
        $self->do( $value );
    }
    $self->commit_transaction();
} #ensure_datastore

sub reset_datastore {
    my $self = shift;
} #reset_datastore

#
# Returns true if the given object traces back to the root.
#
sub has_path_to_root {
    my( $self, $obj_id ) = @_;
    return 1 if $obj_id == 1;
    my $res = $self->selectall_arrayref( "SELECT obj_id FROM field WHERE ref_id=?", $obj_id );
    for my $row (@$res) {
	if( $self->has_path_to_root( @$row ) ) {
	    return 1;
	}
    }

    return 0;
} #has_path_to_root

#
# Return the path to root that this object has, if any.
#
sub path_to_root {
    my( $self, $obj_id ) = @_;
    return '' if $obj_id == 1;
    my $res = $self->selectall_arrayref( "SELECT obj_id,field FROM field WHERE ref_id=?", $obj_id );
    for my $row (@$res) {
	my( $new_obj_id, $field ) = @$row;
	if( $self->has_path_to_root( $new_obj_id ) ) {
	    return $self->path_to_root( $new_obj_id ) . "/$field";
	}
    }

    return undef;
} #path_to_root

sub recycle_object {
    my( $self, $obj_id ) = @_;
    $self->do( "DELETE FROM field WHERE obj_id=?", $obj_id );
    $self->do( "UPDATE objects SET class=NULL,recycled=1 WHERE id=?", $obj_id );
}

# returns the max id (mostly used for diagnostics)
sub max_id {
    my $self = shift;
    my( $highd ) = $self->selectrow_array( "SELECT max(ID) FROM objects" );
    return $highd;
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
# Returns the number of entries in the data structure given.
#
sub xpath_count {
    my( $self, $path ) = @_;
    my( @list ) = _xpath_to_list( $path );
    my $next_ref = 1;
    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar

        my( $ref ) = $self->selectrow_array( "SELECT ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();

        $next_ref = $ref;
        last unless $next_ref;
    } #each path part

    my( $count ) = $self->selectrow_array( "SELECT count(*) FROM field WHERE obj_id=?",  $next_ref );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();


    return $count;

} #xpath_count

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
        my( $val, $ref ) = $self->selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
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
# Returns a hash of paginated items that belong to the xpath.
#
sub paginate_xpath {
    my( $self, $path, $paginate_start, $paginate_length ) = @_;

    my( @list ) = _xpath_to_list( $path );
    my $next_ref = 1;
    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar

        my( $val, $ref ) = $self->selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();


        if( $ref ) {
            $next_ref = $ref;
        }
        else {
	    die "Unable to find xpath location for pagination";
        }
    } #each path part

    my $PAG = '';
    if( defined( $paginate_start ) ) {
	$PAG = "LIMIT $paginate_start";
	if( $paginate_length ) {
	    $PAG .= ",$paginate_length"
	}
    }    

    my $res = $self->selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=? $PAG", $next_ref );
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
    my( $self, $path, $paginate_start, $paginate_length ) = @_;

    my( @list ) = _xpath_to_list( $path );
    my $next_ref = 1;
    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar

        my( $val, $ref ) = $self->selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();


        if( $ref ) {
            $next_ref = $ref;
        }
        else {
	    die "Unable to find xpath location for pagination";
        }
    } #each path part

    my $PAG = '';
    if( defined( $paginate_start ) ) {
	$PAG = "LIMIT $paginate_start";
	if( $paginate_length ) {
	    $PAG .= ",$paginate_length"
	}
    }    

    my $res = $self->selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=? ORDER BY field $PAG", $next_ref );
    my @ret;
    for my $row (@$res) {
	push @ret, $row->[1] || "v$row->[2]";
    }
    return \@ret
} #paginate_xpath_list

#
# Inserts a value into the given xpath. /foo/bar/baz. Overwrites old value if it exists. Appends if it is a list.
#
sub xpath_insert {
    my( $self, $path, $item_to_insert ) = @_;

    my( @list ) = _xpath_to_list( $path );
    my $field = pop @list;
    my $next_ref = 1;
    for my $l (@list) {
        next if $l eq ''; #skip blank paths like /foo//bar/  (should just look up foo -> bar

        my( $val, $ref ) = $self->selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();

        if( $ref ) {
            $next_ref = $ref;
        }
        else {
	    die "Unable to find xpath location for insert";
        }
    } #each path part

    #find the object type to see if this is an array to append to, or a hash to insert to
    if( ref( $item_to_insert ) eq 'ARRAY' ) {
	$self->do( "DELETE FROM field WHERE obj_id = ? AND field=?", $next_ref, $field );
    } else {
	$self->do( "DELETE FROM field WHERE obj_id = ? AND field=?", $next_ref, $field );
    }
    if( index( $item_to_insert, 'v' ) == 0 ) {
	$self->do( "INSERT INTO field (obj_id,field,value) VALUES (?,?,?)", $next_ref, $field, substr( $item_to_insert, 1)  );
    } else {
	$self->do( "INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)", $next_ref, $field, $item_to_insert );
    }

} #xpath_insert

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

        my( $val, $ref ) = $self->selectrow_array( "SELECT value, ref_id FROM field WHERE field=? AND obj_id=?",  $l, $next_ref );
        die $self->{DBH}->errstr() if $self->{DBH}->errstr();

        if( $ref ) {
            $next_ref = $ref;
        }
        else {
	    die "Unable to find xpath location for delete";
        }
    } #each path part

    #find the object type to see if this is an array to append to, or a hash to insert to
    $self->do( "DELETE FROM field WHERE obj_id = ? AND field=?", $next_ref, $field );

} #xpath_delete


#
# Returns a single object specified by the id. The object is returned as a hash ref with id,class,data.
#
sub fetch {
    my( $self, $id ) = @_;
    my( $class ) = $self->selectrow_array( "SELECT class FROM objects WHERE id=?",  $id );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();


    return undef unless $class;
    my $obj = [$id,$class];
    given( $class ) {
        when('ARRAY') {
            $obj->[DATA] = [];
            my $res = $self->selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=?",  $id );
            die $self->{DBH}->errstr() if $self->{DBH}->errstr();

            for my $row (@$res) {
                my( $idx, $ref_id, $value ) = @$row;
		$obj->[DATA][$idx] = $ref_id || "v$value";
            }
        }
        default {
            $obj->[DATA] = {};
            my $res = $self->selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=?",  $id );
            die $self->{DBH}->errstr() if $self->{DBH}->errstr();

            for my $row (@$res) {
                my( $field, $ref_id, $value ) = @$row;
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

    my( $recycled_id ) = $self->do( "SELECT id FROM objects WHERE recycled=1 LIMIT 1" );
    if( int($recycled_id) > 0 ) {
	$self->do( "UPDATE objects SET recycled=0 WHERE id=?", $recycled_id );
	return $recycled_id;
    }
    my $res = $self->do( "INSERT INTO objects (class) VALUES (?)",  $class );
    die $self->{DBH}->errstr() if $self->{DBH}->errstr();

    return $self->{DBH}->last_insert_id(undef,undef,undef,undef);
} #get_id

sub apply_updates {
    my( $self, $upds ) = @_;

    for my $up (@$upds) {
	$self->do( @$upds );
	die $self->{DBH}->errstr() if $self->{DBH}->errstr();
    }
} #apply_updates

sub stow {
    my( $self, $id, $class, $data ) = @_;

    my $updates = $self->stow_updates( $id, $class, $data );

    for my $upd (@$updates) {
	$self->do( @$upd );
	die $self->{DBH}->errstr() if $self->{DBH}->errstr();
    }

} #stow

#
# Stores the object to persistance. Object is an array ref in the form id,class,data
#
sub stow_updates {
    my( $self, $id, $class, $data ) = @_;

    my( @cmds );

    given( $class ) {
        when('ARRAY') {
            push( @cmds, ["DELETE FROM field WHERE obj_id=?",  $id ] );


            for my $i (0..$#$data) {
		next unless defined $data->[$i];
                my $val = $data->[$i];
                if( index( $val, 'v' ) == 0 ) {
		    push( @cmds, ["INSERT INTO field (obj_id,field,value) VALUES (?,?,?)",  $id, $i, substr($val,1) ] );
                } else {
                    push( @cmds, ["INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)",  $id, $i, $val ] );

                }
            }
        }
        default {
            push( @cmds, ["DELETE FROM field WHERE obj_id=?",  $id ] );
            for my $key (keys %$data) {
                my $val = $data->{$key};
                if( index( $val, 'v' ) == 0 ) {
		    push( @cmds, ["INSERT INTO field (obj_id,field,value) VALUES (?,?,?)",  $id, $key, substr($val,1) ] );
                }
                else {
                    push( @cmds, ["INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)",  $id, $key, $val ] );
                }
            } #each key
        }
    }
    return \@cmds;
} # stow_updates


1;
__END__

=head1 NAME

Yote::SQLiteIO - A SQLite persistance engine for Yote.

=head1 DESCRIPTION

This can be installed as a singleton of Yote::ObjProvider and does the actual storage and retreival of Yote objects.

=head1 CONFIGURATION

The package name is used as an argument to the Yote::ObjProvider package which also takes the configuration parameters for Yote::SQLiteIO.

Yote::ObjProvider::init( datastore => 'Yote::SQLiteIO', db => 'yote_db', uname => 'yote_db_user', pword => 'yote_db_password' );


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
