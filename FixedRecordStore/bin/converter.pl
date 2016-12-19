#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Data::RecordStore;

my( $from_dir, $to_dir ) = @ARGV;
die "Usage : converter.pl <db source dir> <db target dir>" unless $from_dir && $to_dir;

my $old_obj_idx_file = "$from_dir/OBJ_INDEX";
my $new_obj_idx_file = "$to_dir/OBJ_INDEX";
die "Database not found in directory '$from_dir'" unless -f $old_obj_idx_file;

my $ver_file = "$from_dir/VERSION";
my $from_version = 1;
if( -e $ver_file ) {
    open my $FH, "<", $ver_file;
    $from_version = <$FH>;
    chomp $from_version;
    close $FH;
}

if( $from_version >= 2 ) {
    print STDERR "Database already at version '$from_version'. Doing nothing\n";
    exit;
}

die "Directory '$to_dir' already exists" if -d $to_dir;

print STDERR "Creating destination dir\n";

mkdir $to_dir or die "Unable to create directory '$to_dir'";
mkdir "$to_dir/stores" or die "Unable to create directory '$to_dir/stores'";

print STDERR "Copying object index database\n";
`cp $old_obj_idx_file $new_obj_idx_file`;

print STDERR "Starting Convert from $from_version to $Data::RecordStore::VERSION\n";

my $store_db = Data::RecordStore::FixedStore->open( "I", "$from_dir/STORE_INDEX" );

#my @old_sizes;
my $old_dbs = [];
my $new_dbs = [];

for my $id (1..$store_db->entry_count) {
    my( $size ) = @{ $store_db->get_record( $id ) };
#    $old_sizes[$id] = $size;

    $old_dbs->[$id] = Data::RecordStore::FixedStore->open( "A*", "$from_dir/${id}_OBJSTORE", $size );
    
#    my( $data ) = @{ $old_dbs->[$id]->get_record( 1 ) };
#    print STDERR "$id:0) $data\n";
}


my $obj_db = Data::RecordStore::FixedStore->open( "IL", $old_obj_idx_file );

my $tenth = int($obj_db->entry_count/10);
my $count = 0;

for my $id (1..$obj_db->entry_count) {
    my( $old_store_id, $id_in_old_store ) = @{ $obj_db->get_record( $id ) };

    print STDERR "id ($id) in $old_store_id/$id_in_old_store\n";next;

    
    next unless $id_in_old_store;

    # grab data
    my $old_db = $old_dbs->[$old_store_id];
    # unless( $old_db ) {
    #     $old_db = Data::RecordStore::FixedStore->open( "A*", "$from_dir/${old_store_id}_OBJSTORE", $old_sizes[$old_store_id] );
    #     $old_dbs->[$old_store_id] = $old_db;
    # }
    my( $data ) = @{ $old_db->get_record( $id_in_old_store ) };


    print STDERR substr( $data, 0, 100 ) if index($data,"HASH") != 0;
    
    next;
    

    # store in new database
    my $save_size = do { use bytes; length( $data ); };
    $save_size += 8; #for the id
    my $new_store_id = 1 + int( log( $save_size ) );
    my $new_store_size = int( exp $new_store_id );

    my $new_db = $new_dbs->[$new_store_id];
    unless( $new_db ) {
        $new_db = Data::RecordStore::FixedStore->open( "IA*", "$to_dir/stores/${new_store_id}_OBJSTORE", $new_store_size );
        $new_dbs->[$new_store_id] = $new_db;
    }
    my $idx_in_new_store = $new_db->next_id;
    $new_db->put_record( $idx_in_new_store, [ $id, $data ] );

    $obj_db->put_record( $id, [ $new_store_id, $idx_in_new_store ] );
    if( ++$count > $tenth ) {
        print STDERR ".";
        $count = 0;
    }

}
print STDERR "\n";

print STDERR "Adding version information\n";

open my $FH, ">", "$to_dir/VERSION";
print $FH "$Data::RecordStore::VERSION\n";
close $FH;


print STDERR "Done\n";
