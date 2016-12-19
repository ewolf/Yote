#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Data::RecordStore;

die "Converter requires Data::RecordStore version of at least 2.0" unless $Data::RecordStore::VERSION >= 2;

my( $source_dir, $dest_dir ) = @ARGV;
die "Usage : converter.pl <db source dir> <db target dir>" unless $source_dir && $dest_dir;

my $source_obj_idx_file = "$source_dir/OBJ_INDEX";
my $dest_obj_idx_file = "$dest_dir/OBJ_INDEX";
die "Database not found in directory '$source_dir'" unless -f $source_obj_idx_file;

my $ver_file = "$source_dir/VERSION";
my $source_version = 1;
if( -e $ver_file ) {
    open my $FH, "<", $ver_file;
    $source_version = <$FH>;
    chomp $source_version;
    close $FH;
}

if( $source_version >= 2 ) {
    print STDERR "Database at '$source_dir' already at version $source_version. Doing nothing\n";
    exit;
}

print STDERR "Convert from $source_version to $Data::RecordStore::VERSION\n";


die "Directory '$dest_dir' already exists" if -d $dest_dir;

print STDERR "Creating destination dir\n";

mkdir $dest_dir or die "Unable to create directory '$dest_dir'";
mkdir "$dest_dir/stores" or die "Unable to create directory '$dest_dir/stores'";

print STDERR "Starting Convertes from $source_version to $Data::RecordStore::VERSION\n";

my $store_db = Data::RecordStore::FixedStore->open( "I", "$source_dir/STORE_INDEX" );

#my @old_sizes;
my $source_dbs = [];
my $dest_dbs = [];

for my $id (1..$store_db->entry_count) {
    my( $size ) = @{ $store_db->get_record( $id ) };
#    $source_sizes[$id] = $size;

    $source_dbs->[$id] = Data::RecordStore::FixedStore->open( "A*", "$source_dir/${id}_OBJSTORE", $size );
    
#    my( $data ) = @{ $source_dbs->[$id]->get_record( 1 ) };
#    print STDERR "$id:0) $data\n";
}


my $source_obj_db = Data::RecordStore::FixedStore->open( "IL", $source_obj_idx_file );
my $dest_obj_db = Data::RecordStore::FixedStore->open( "IL", $dest_obj_idx_file );
$dest_obj_db->ensure_entry_count($source_obj_db->entry_count);

my $tenth = int($source_obj_db->entry_count/10);
my $count = 0;

for my $id (1..$source_obj_db->entry_count) {
    my( $source_store_id, $id_in_old_store ) = @{ $source_obj_db->get_record( $id ) };

#    print STDERR "id ($id) in $source_store_id/$id_in_old_store\n";next;

    
    next unless $id_in_old_store;

    # grab data
    my( $data ) = @{ $source_dbs->[$source_store_id]->get_record( $id_in_old_store ) };

    # store in new database
    my $save_size = do { use bytes; length( $data ); };
    $save_size += 8; #for the id
    my $dest_store_id = 1 + int( log( $save_size ) );
    my $dest_store_size = int( exp $dest_store_id );

    my $dest_db = $dest_dbs->[$dest_store_id];
    unless( $dest_db ) {
        $dest_db = Data::RecordStore::FixedStore->open( "LZ*", "$dest_dir/stores/${dest_store_id}_OBJSTORE", $dest_store_size );
        $dest_dbs->[$dest_store_id] = $dest_db;
    }
    my $idx_in_dest_store = $dest_db->next_id;
    $dest_db->put_record( $idx_in_dest_store, [ $id, $data ] );

    $dest_obj_db->put_record( $id, [ $dest_store_id, $idx_in_dest_store ] );
    if( ++$count > $tenth ) {
        print STDERR ".";
        $count = 0;
    }

}
print STDERR "\n";

print STDERR "Adding version information\n";

open my $FH, ">", "$dest_dir/VERSION";
print $FH "$Data::RecordStore::VERSION\n";
close $FH;


print STDERR "Done. Remember that your new database is in $dest_dir and your old one is in $source_dir\n";
