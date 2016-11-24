#!/usr/bin/perl

use Yote;
use Yote::Server;
use Data::Dumper;

my $db_dir = shift @ARGV || '/opt/yote/DATA_STORE';
my $store = Yote::open_store( $db_dir );

show( $store->fetch_root->{ID} );

print ">";

while( my $in = <STDIN> ) {
    chomp $in;
    if( $in > 0 ) {
        show( $in );
    }
    print "\n>";
}

exit;

sub show {
    my $id = shift;
    my $obj = $store->fetch( $id );
    unless( $obj ) {
        print "Nothing found for id $id\n";
        return;
    }
    my $r = ref( $obj );
    if( $r eq 'HASH' ) {
        print "$id is hash with ".scalar(keys %$obj)." keys\n";
        for my $key (sort keys %$obj) {
            print "\t$key => ".$store->_xform_out( $obj->{$key} )."\n";
        }
    }
    elsif( $r eq 'ARRAY' ) {
        print "$id is array with ".scalar(@$obj)." elements\n";
        for( my $i=0; $i<@$obj; $i++ ) {
            print "\t$i) ".$store->_xform_out( $obj->[$i] )."\n";
        }
    }
    else {
        print "$id is $r\n\t".join("\n\t",map { "$_ => $obj->{DATA}{$_}" }
                                 keys %{$obj->{DATA}} )."\n";
    }
}


   


__END__

a command line explorer for a yote database.

Can view and edit.


