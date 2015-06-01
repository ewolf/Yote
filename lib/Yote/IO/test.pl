use Yote::IO::YoteDB;

use strict;

my $ydb = new Yote::IO::YoteDB( { store => "/tmp/YSTORE" } );

for my $n ( qw( aaaaa bbuh celiiii dala  efflo fooooo  goo )) {
    my $id = $ydb->get_id;
    $ydb->stow( [$id, "", $n] );
}

for my $id (1..7) {
    my $v = $ydb->fetch( $id );
    print STDERR Data::Dumper->Dump(["GETTING $id",$v]);
}
print STDERR Data::Dumper->Dump(["AND",(7..1)]);
for( my $id=7; $id>0; $id--){
    my $v = $ydb->fetch( $id );
    print STDERR Data::Dumper->Dump(["getting $id",$v]);
}
