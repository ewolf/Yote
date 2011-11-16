package GServ::ObjIO;

#
# This stows and fetches G objects from a database store and provides object ids.
#

use strict;
use feature ':5.10';

use Data::Dumper;
use DBI;

my $DBH = DBI->connect( 'DBI:mysql:sg' );

use constant { 
    DATA => 2,
    MAX_LENGTH => 1025,
};

sub init_database {
    my $database = shift;
    database( DBI->connect( "DBI:mysql:$database" ) );

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
                      ) ENGINE=MyISAM DEFAULT CHARSET=latin1~,
	objects => q~CREATE TABLE `objects` (
                     `id` int(11) NOT NULL AUTO_INCREMENT,
                     `class` varchar(255) DEFAULT NULL,
                      PRIMARY KEY (`id`)
                      ) ENGINE=InnoDB DEFAULT CHARSET=latin1~
	);
    DBI->selectrow_array( "START TRANSACTION" );
    my $today = DBI->selectrow_array( "SELECT now()" );
    $today =~ s/ /T/;
    for my $t (keys %definitions ) {
	my( $t ) = DBI->selectrow_array( "SHOW TABLES LIKE '$t'" );
	if( $t ) {
	    my $existing_def = DBI->selectall_array( "SHOW CREATE TABLE $t" );	    
	    my $current_def = $definitions{$t};

	    #normalize whitespace for comparison
	    $current_def =~ s/[\s\n\r]+/ /gs; 
	    $existing_def =~ s/[\s\n\r]+/ /gs; 
	    
	    if( lc( $current_def ) eq lc( $existing_def ) ) {
		print STDERR "Table '$t' exists and is the same version\n";
	    } else {
		my $backup = "${t}_$today";
		print STDERR "Table definition mismatch for $t. Rename old table '$t' to '$backup' and creating new one.\n";
		DBI->do("RENAME TABLE $t TO $backup\n");
		DBI->do( $definitions{$t} );
	    }
	} else {
	    print STDERR "Creating table $t\n";
	    DBI->do( $definitions{$t} );
	}
    }
    DBI->selectrow_array( "COMMIT" );
} #init_database

sub database {
    my( $db ) = @_;
    if( $db ) {
        $DBH = $db;
    }
    return $DBH;
}

#
# Returns the number of entries in the data structure given.
#
sub xpath_count {
    my $path = shift;
    my( @list ) = split( /\//, $path );
    my $next_ref = 1;
    for my $l (@list) {
        next unless $l; #skip blank paths like /foo//bar/  (should just look up foo -> bar
        my( $val, $ref ) = $DBH->selectrow_array( "SELECT field, ref_id FROM field WHERE field=? AND obj_id=?", {}, $l, $next_ref );
	$next_ref = $ref;
	last unless $next_ref;
    } #each path part

    my( $count ) = $DBH->selectrow_array( "SELECT count(*) FROM field WHERE obj_id=?", {}, $next_ref );

    return $count;
    
} #xpath_count

#
# Returns a single value given the xpath (hash only, and notation is slash separated from root)
# This will always query persistance directly for the value, bypassing objects.
# The use for this is to fetch specific things from potentially very long hashes that you don't want to
#   load in their entirety.
#
sub xpath {
    my( $path ) = @_;
    my( @list ) = split( /\//, $path );
    my $next_ref = 1;
    my $final_val;
    for my $l (@list) {
        next unless $l; #skip blank paths like /foo//bar/  (should just look up foo -> bar
        undef $final_val;
        my( $val, $ref ) = $DBH->selectrow_array( "SELECT field, ref_id FROM field WHERE field=? AND obj_id=?", {}, $l, $next_ref );
        if( $ref && $val ) {
            my ( $big_val ) = $DBH->selectrow_array( "SELECT text FROM big_text WHERE obj_id=?", {}, $ref );
            $final_val = "v$big_val";
        } elsif( $ref ) {
            $next_ref = $ref;
            $final_val = $ref;
        } else {
            $final_val = "v$val";
        }
    } #each path part

    # @TODO: log bad xpath if final_value not defined

    return $final_val;
} #xpath

#
# Returns a list of objects as a result : All objects connected to the one specified
# by the id.
#
# The objects are returned as array refs with 3 fields :
#   id, class, data
#
sub fetch_deep {
    my( $id, $seen ) = @_;
    
    $seen ||= {};

    my( $class ) = $DBH->selectrow_array( "SELECT class FROM objects WHERE id=?", {}, $id );

    return undef unless $class;
    my $obj = [$id,$class];
    given( $class ) {
        when('ARRAY') {
            $obj->[DATA] = [];
        }
        default {
            $obj->[DATA] = {};
        } 
    }

    $seen->{$id} = $obj;

    given( $class ) {
        when('ARRAY') {
            my $res = $DBH->selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=?", {}, $id );
            for my $row (@$res) {
                my( $idx, $ref_id, $value ) = @$row;
                $obj->[DATA][$idx] = $ref_id || $value;
                if( $ref_id ) {
                    fetch_deep( $ref_id, $seen );
                }
            }
        }
        when('BIGTEXT') {
            ($obj->[DATA]) = $DBH->selectrow_array( "SELECT text FROM big_text WHERE obj_id=?", {}, $id );
        }
        default {
            my $res = $DBH->selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=?", {}, $id );
            for my $row (@$res) {
                my( $field, $ref_id, $value ) = @$row;
                $obj->[DATA]{$field} = $ref_id || $value;
                if( $ref_id ) {
                    fetch_deep( $ref_id, $seen );
                }
            }
        } # hash or object
    }    

    return [values %$seen];
} #fetch_deep

#
# Returns a single object specified by the id. The object is returned as a hash ref with id,class,data.
#
sub fetch {
    my( $id ) = @_;

    my( $class ) = $DBH->selectrow_array( "SELECT class FROM objects WHERE id=?", {}, $id );
    return undef unless $class;
    my $obj = [$id,$class];
    given( $class ) {
        when('ARRAY') {
            $obj->[DATA] = [];
            my $res = $DBH->selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=?", {}, $id );
            for my $row (@$res) {
                my( $idx, $ref_id, $value ) = @$row;
                if( $ref_id && $value ) {
                    my( $val ) = $DBH->selectrow_array( "SELECT text FROM big_text WHERE obj_id=?", {}, $ref_id );
                    ( $obj->[DATA][$idx] ) = "v$val";
                } else {
                    $obj->[DATA][$idx] = $ref_id || "v$value";
                }
            }
        }
        default {
            $obj->[DATA] = {};
            my $res = $DBH->selectall_arrayref( "SELECT field, ref_id, value FROM field WHERE obj_id=?", {}, $id );
            for my $row (@$res) {
                my( $field, $ref_id, $value ) = @$row;
                if( $ref_id && $value ) {
                    my( $val ) = $DBH->selectrow_array( "SELECT text FROM big_text WHERE obj_id=?", {}, $ref_id );
                    ( $obj->[DATA]{$field} ) = "v$val";
                } else {
                    $obj->[DATA]{$field} = $ref_id || "v$value";
                }
            }
        } 
    }
    return $obj;
} #fetch

#
# Given a class, makes new entry in the objects table and returns the generated id
#
sub get_id {
    my( $class ) = @_;

    my $res = $DBH->do( "INSERT INTO objects (class) VALUES (?)", {}, $class );
    return $DBH->last_insert_id(undef,undef,undef,undef);
} #get_id

#
# Stores the object to persistance. Object is an array ref in the form id,class,data
#
sub stow {
    my( $id, $class, $data ) = @_;
    given( $class ) {
        when('ARRAY') {
            $DBH->do( "DELETE FROM field WHERE obj_id=?", {}, $id );
            for my $i (0..$#$data) {
                my $val = $data->[$i];
                if( index( $val, 'v' ) == 0 ) {
                    if( length( $val ) > MAX_LENGTH ) {
                        my $big_id = get_id( "BIGTEXT" );
                        $DBH->do( "INSERT INTO field (obj_id,field,ref_id,value) VALUES (?,?,?,'V')", {}, $id, $i, $big_id );
                        $DBH->do( "INSERT INTO big_text (obj_id,text) VALUES (?,?)", {}, $big_id, substr($val,1) );
                    } else {                    
                        $DBH->do( "INSERT INTO field (obj_id,field,value) VALUES (?,?,?)", {}, $id, $i, substr($val,1) );
                    }
                } else {
                    $DBH->do( "INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)", {}, $id, $i, $val );
                }
            }
        }
        default {
            $DBH->do( "DELETE FROM field WHERE obj_id=?", {}, $id );
            for my $key (keys %$data) {
                next if $key eq '__ID__';
                my $val = $data->{$key};
                if( index( $val, 'v' ) == 0 ) {
                    if( length( $val ) > MAX_LENGTH ) {
                        my $big_id = get_id( "BIGTEXT" );
                        $DBH->do( "INSERT INTO field (obj_id,field,ref_id,value) VALUES (?,?,?,'V')", {}, $id, $key, $big_id );
                        $DBH->do( "INSERT INTO big_text (obj_id,text) VALUES (?,?)", {}, $big_id, substr($val,1) );
                    } else {                    
                        $DBH->do( "INSERT INTO field (obj_id,field,value) VALUES (?,?,?)", {}, $id, $key, substr($val,1) );
                    } 
                }
                else {
                    $DBH->do( "INSERT INTO field (obj_id,field,ref_id) VALUES (?,?,?)", {}, $id, $key, $val );
                }
            } #each key
        }
    }    
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
