#!/usr/bin/perl

use strict;

use G::Base;
use G::GameHangar;
use G::Array;
use G::Hash;

main();

sub main {
    if(0) {
        print STDERR "START\n";
        if($ARGV[0]) {
            my $d = get_data();
            show($d);
            exit;
        }


        if( 1 ) {
            G::Base::do_query("truncate account");
	    G::Base::do_query("truncate field");
            G::Base::do_query("truncate objects");
            G::Base::do_query("truncate session");
            G::Base::do_query("truncate toplevel");
            G::Base::do_query("truncate array");
        }

	my $H = G::GameHangar::get_hangar();
	$H->create_account( 'x', 'x', 'x' );
	my( $acct, $sess ) = $H->login( { uname => 'x', pword => 'x' } );

	exit(0);

        my $d1 = get_data(1);
        show($d1);
        print STDERR "----------------------\n";
#        G::Base::save_all();
        exit;
    }
    my $d1 = get_data(1);
    my $d2 = get_data();

    my $failed;
    if( compare( $d1, $d2 ) ) {
        print STDERR  "Passed\n";
    } else {
        $failed = 1;
        print STDERR  "Failed\n";
    }

    
    my $d3 = get_data();
    
    if( compare( $d2, $d3 ) ) {
        print STDERR  "Passed\n";
    } else {
        $failed = 1;
        print STDERR  "Failed\n";
    }

    $G::Base::CACHE->{max_buckets} = 2;
    $G::Base::CACHE->{bucket_size} = 5;
    my $d4 = get_data();

    $d3->set_cooltest('mostcool');

    if( compare( $d3, $d4 ) ) {
        print STDERR  "Passed\n";
    } else {
        $failed = 1;
        print STDERR  "Failed\n";
    }
    
    if( $failed ) {
        print STDERR  "Tests failed\n";
    } else {
        print STDERR  "Tests passed\n";
    }

} #main

sub compare {
    my( $d1, $d2, $level ) = @_;

    print STDERR  ' ' x $level;
    print STDERR  "Comparing '$d1' vs '$d2'\n";

    if( ref( $d1 ) eq 'ARRAY' ) {
        unless(  ref( $d2 ) eq 'ARRAY' ) {
            print STDERR  "Ref 2 : '".ref($d2)."'\n";
            return 0 ;
        }
        unless( @$d1 == @$d2 ) {
            print STDERR  scalar(@$d1).' vs '.scalar(@$d2)."\n";
            return 0;
        }
        for( my $i=0; $i<@$d1; ++$i ) {
            return 0 unless compare( $d1->[$i], $d2->[$i], 1 + $level );
        }
    } elsif( ref( $d1 ) eq 'HASH' ) {
        unless( ref( $d2 ) eq 'HASH' ) {
            print STDERR  "2nd reference '".ref($d2)."'\n";
            return 0 ;
        }
        my( @k1 ) = keys %$d1;
        my( @k2 ) = keys %$d2;
        unless( @k1 == @k2 ) {
            print STDERR  scalar(@k1).' vs '.scalar(@k2)."\n";
            return 0;
        }
        for my $k (@k1) {
            print STDERR  ' ' x $level;
            print STDERR  "key '$k'\n";
            return 0 unless compare( $d1->{$k}, $d2->{$k}, 1 + $level );
        }
    } elsif( ref( $d1 ) =~ /^G::(Array|Hash|Ref)/ ) {
        return 0 unless ref( $d2 ) =~ /^G::(Array|Hash|Ref)/;
        return compare( $d1->dereference(), $d2->dereference(), 1 + $level );
    } elsif( ref( $d1 ) ) {
        print STDERR  ' ' x $level;
        print STDERR  "ids : $d1->{ID} vs $d2->{ID}\n";
        return 0 unless ref( $d2 ) && $d1->{ID} == $d2->{ID};
        return compare( $d1->{DATA}, $d2->{DATA}, 1 + $level );
    } else {
        return $d1 eq $d2;
    }

    return 1;
} #compare

sub get_data {
    my $write = shift;

    my $file = 'UTEST.DAT';
    if( $write ) {
        my $top = new G::Base();
        print STDERR "__________________=======+***************___________\n";
        my $t2 = new G::Base();
	my $t3 = new G::Base();
	my $t4 = new G::Base();
	my $t5 = new G::Base();
	my $t6 = new G::Base();
	$t4->set_obj( $t5 );
	my $a1 = $t5->set_oarry( [] );
	my $h2 = $t5->set_ohsh( {} );
	push( @$a1, $t6 );
	$h2->{coolness} = $t6;
	$t3->set_yeah('no');
	$top->set_tthree($t3);
        my $arry = $top->get_arry([]);
        push( @$arry, { foo => $t2,
                        bar => { this => "is more" },
                        baz => [ 'yet', 'more', 'stuff',[1,2,3],[4,5,6],[6,7,6],{ this=>"coolie", justendouth=>"references", "do I" => "love it", [4.2,4,5,6,2],[0] } ],
              } );
        
        open( OUT, ">$file" );
        print OUT "$top->{ID}\n";

        close( OUT );
#        print STDERR Data::Dumper->Dump( [$top,$t2] );
        G::Base::save_all();
    } 

    open( IN,  "<$file" );
    my $id = <IN>;
    chomp( $id );
    print "Trying to fetch $id\n";
    my $top = G::Base::fetch( $id );
    close( IN );    
    return $top;
}


sub show {
    my $x = shift;
    my $ind = shift || 0;
    print STDERR  ' ' x $ind;
    if( ref( $x ) eq 'ARRAY' ) {
        print STDERR  "Array. ID is $G::Base::OBJ2ID->{$x}. Contents : \n";
        for my $item (@$x) {
            show( $item, $ind + 1 );
        }
    } elsif( ref( $x ) eq 'HASH' ) {
        print STDERR  "Hash. ID is $G::Base::OBJ2ID->{$x}. Contents : \n";
        for my $key (keys %$x) {
            print STDERR  ' ' x $ind;
            print STDERR  "$key :\n";
            show( $x->{$key}, $ind + 1 );
        }        
    } elsif( ref( $x ) ) {
        print STDERR  "G Object $x with ID $x->{ID}\n"; 
        for my $key (keys %{$x->{DATA}}) {
            print STDERR  ' ' x $ind;
            print STDERR  "$key :\n";
            show( $x->{DATA}{$key}, $ind + 1 );
        }
    } else {
        print STDERR  "Scalar value | $x\n";
    }
}

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut
