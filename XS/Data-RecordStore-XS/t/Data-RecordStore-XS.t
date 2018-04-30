# Before 'make install' is performed this script should be runnable with
# 'make test'. After 'make install' it should work as 'perl Data-RecordStore-XS.t'

#########################

# change 'tests => 1' to 'tests => last_test_to_print';

use strict;
use warnings;

use Test::More tests => 1;
BEGIN { use_ok('Data::RecordStore::XS') };

diag( "HELLO" );

#########################

# Insert your test code below, the Test::More module is use()ed here so read
# its man page ( perldoc Test::More ) for help writing this test script.

my $store = Data::RecordStore::XS::open_store( "/tmp/FOOS" );
diag( "Opened $store" );
my $id = $store->next_id;
diag( "Got ID $id" );
