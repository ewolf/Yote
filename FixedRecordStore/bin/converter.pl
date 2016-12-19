#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;
use Data::RecordStore;

my( $dir ) = @ARGV;
die "Usage : converter.pl <directory with db>" unless $dir;

my $obj_idx_file = "$dir/OBJ_INDEX";
die "Database not found in directory '$dir'" unless -f $obj_idx_file;

my $ver_file = "$dir/VERSION";
my $from_version = 1;
if( -e $ver_file ) {
    open my $FH, "<", $ver_file;
    $from_version = <$FH>;
    chomp $from_version;
    close $FH;
}
print STDERR "Convert from $from_version to $Data::RecordStore::VERSION\n";

#
# move databases to backup
#
mkdir "$dir/old_db";

my $store_db = Data::RecordStore::FixedStore->open( "I", "$dir/STORE_INDEX" );
my @old_sizes;
for my $id (1..$store_db->entry_count) {
    my( $size ) = @{ $store_db->get_record( $id ) };
    $old_sizes[$id] = $size;
    rename "$dir/${id}_OBJSTORE", "$dir/old_db/${id}_OBJSTORE";
    rename "$dir/${id}_OBJSTORE.recycle", "$dir/old_db/${id}_OBJSTORE.recycle";
}
my $old_dbs = [];
my $new_dbs = [];

my $obj_db = Data::RecordStore::FixedStore->open( "IL", $obj_idx_file );
for my $id (1..$obj_db->entry_count) {
    my( $old_store_id, $id_in_old_store ) = @{ $obj_db->get_record( $id ) };

    # grab data
    my $old_db = $old_dbs->[$old_store_id];
    unless( $old_db ) {
        $old_db = Data::RecordStore::FixedStore->open( "A*", "$dir/old_db/${old_store_id}_OBJSTORE", $old_sizes[$old_store_id] );
        $old_dbs->[$old_store_id] = $old_db;
    }
    my( $data ) = @{ $old_db->get_record( $id_in_old_store ) };

    # store in new database
    my $save_size = do { use bytes; length( $data ); };
    $save_size += 8; #for the id
    my $new_store_id = 1 + int( log( $save_size ) );
    my $new_store_size = int( exp $new_store_id );

    my $new_db = $new_dbs->[$new_store_id];
    unless( $new_db ) {
        $new_db = Data::RecordStore::FixedStore->open( "IA*", "$dir/stores/${new_store_id}_OBJSTORE", $new_store_size );
        $new_dbs->[$new_store_id] = $new_db;
    }
    my $idx_in_new_store = $new_db->next_id;
    $new_db->put_record( $idx_in_new_store, [ $id, $data ] );

    $obj_db->put_record( $id, [ $new_store_id, $idx_in_new_store ] );
}

open my $FH, ">", $ver_file;
print $FH "$Data::RecordStore::VERSION\n";
close $FH;


# test to make sure it works
unlink "$dir/old_db";
