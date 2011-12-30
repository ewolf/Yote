package SE::UnitTest;

#
# This is a test module for Stellar Expanse.
#
# This creates a game with a known map, three players and ships for those players and sector ownership for
# those players.
#
#

#
# Test all commands in different situations :
#   * Build 
#   * Name - name things that are yours/are not yours
#   * Move 
#   Unload 
#   Load
#   Fire
#   Repair
#   Give
#  
#   Indict and system conquering
#
# * done and passes
#

use strict;

use G::Account;
use SE::StellarExpanse;

use Carp ();
local $SIG{__DIE__} = sub { &Carp::confess };


sub new {
    my $ref = shift;
    my $class = ref( $ref ) || $ref;
    my $self = {};
    return bless $self, $class;
} #new


sub test_game {
    my $self = shift;

    $self->set_up();
    $self->build();
    $self->rename();
    $self->move();
    $self->fire();

    my $g = $self->{g};
    check( 'valid map', $g->verify_map(), 1 );
    
    print "\nPassed all tests\n";
} #test_game

sub move {
    my $self = shift;

    my ( $a1, $a2, $a3, $g ) = ( $self->{a1},$self->{a2},$self->{a3},$self->{g} );
    my $sectors = $self->{sectors};

    my $players = $g->get_players();
    my $p1 = $players->{$a1->{ID}};
    my $p2 = $players->{$a2->{ID}};
    my $p3 = $players->{$a3->{ID}};

    my $s0_id = $sectors->[0]{ID};
    my $s1_id = $sectors->[1]{ID};
    my $s2_id = $sectors->[2]{ID};
    my $s3_id = $sectors->[3]{ID};
    my $s4_id = $sectors->[4]{ID};
    my $s5_id = $sectors->[5]{ID};
    my $s6_id = $sectors->[6]{ID};
    my $s7_id = $sectors->[7]{ID};
    my $s8_id = $sectors->[8]{ID};

    my( $p1ship ) = @{ $p1->get_state('ships') }; #scout
    my( $p2ship ) = @{ $p2->get_state('ships') }; #cruizer
    my( $p3scout, $p3boat ) = @{ $p3->get_state('ships') };

    my( $no_id ) = G::Base::query_line( "select 2*max(id) from objects" );

    my $p1_fail_a = [ "M $p1ship->{ID} $s3_id" ];
    my $p1_succ = [
        "M $p1ship->{ID} $s1_id",
        "M $p1ship->{ID} $s2_id",
	"M $p1ship->{ID} $s3_id",
        "M $p1ship->{ID} $s4_id",
        "M $p1ship->{ID} $s3_id",
        ];
    my $p1_fail_b = [ "M $p1ship->{ID} $s2_id",
                      "M $p2ship->{ID} $s4_id",
                      "M $no_id $s4_id",
        ];
    my $p1_fail_msg = [
        "cannot reach",
        'enough move',
        'not found',
        'not found',
        ];
    

    $p1->set_next_state('orders',[ @$p1_fail_a, @$p1_succ, @$p1_fail_b ] );

    $g->advance_turn();
    check( 'turn', $g->get_turn(), 4 );
    check_messages( $p1, $p1_succ, [@$p1_fail_a,@$p1_fail_b],$p1_fail_msg );

    my $p1_succ = [ "M $p1ship->{ID} $s4_id" ];
    $p1->set_next_state('orders', $p1_succ );

    $g->advance_turn();
    check( 'turn', $g->get_turn(), 5 );

    check_messages( $p1, $p1_succ );
    

    my $p2_succ = [ "M $p2ship->{ID} $s4_id" ];
    my $p2_fail = [ "M $p2ship->{ID} $s3_id" ];
    my $p2_fail_msg = [ "enough move" ];
    $p2->set_next_state( 'orders', [ @$p2_succ, @$p2_fail ] );

    $g->advance_turn();
    check( 'turn', $g->get_turn(), 6 );

    check_messages( $p2, $p2_succ, $p2_fail );
    check( 'owner', $sectors->[4]->get_state('owner'), $p2 );

    my $p3_succ = ["M $p3scout->{ID} $s7_id",
                   "M $p3scout->{ID} $s6_id",
                   "M $p3scout->{ID} $s5_id",
                   "M $p3scout->{ID} $s4_id",
                   "M $p3boat->{ID} $s7_id",
		   "M $p3boat->{ID} $s6_id",
		   "M $p3boat->{ID} $s5_id",
		   "M $p3boat->{ID} $s4_id",
	];
    my $p3_fail = [
        ];
    my $p3_fail_msg = [];
    my $p3_tags = [ "Move scout to 7", "Move scout to 6", "Move scout to 5", "Move scout to 4",
		    "MOve batboat to 7", "Move patboat to 6","MOve batboat to 5", "Move patboat to 4" ];
    $p3->set_next_state( 'orders', [@$p3_succ,@$p3_fail] );
    $g->advance_turn();
    check( 'turn', $g->get_turn(), 7 );

    check_messages( $p3, $p3_succ, $p3_fail, $p3_fail_msg, [], $p3_tags );

    my $p2map = $p2->get_state('maps');
    check( 'known location', ref $p2map->{$s4_id}->get_system(), 'SE::Sector' );

    my $sec_ships = $sectors->[4]->get_state('ships');
    check( 'ship count in sector 4', scalar( @$sec_ships ), 4 );
    
} #move


sub fire {
    my $self = shift;

    my ( $a1, $a2, $a3, $g ) = ( $self->{a1},$self->{a2},$self->{a3},$self->{g} );
    my $sectors = $self->{sectors};

    my $players = $g->get_players();
    my $p1 = $players->{$a1->{ID}};
    my $p2 = $players->{$a2->{ID}};
    my $p3 = $players->{$a3->{ID}};

    my $s0_id = $sectors->[0]{ID};
    my $s1_id = $sectors->[1]{ID};
    my $s2_id = $sectors->[2]{ID};
    my $s3_id = $sectors->[3]{ID};
    my $s4_id = $sectors->[4]{ID};
    my $s5_id = $sectors->[5]{ID};
    my $s6_id = $sectors->[6]{ID};
    my $s7_id = $sectors->[7]{ID};
    my $s8_id = $sectors->[8]{ID};

    my( $p1sct ) = @{ $p1->get_state('ships') }; 
    my( $p2cruiz, $p2c2, $p2sc, $p2gub ) = @{ $p2->get_state('ships') }; 
    my( $p3scout, $p3boat ) = @{ $p3->get_state('ships') }; #cruizer
    my( $no_id ) = G::Base::query_line( "select 10 + max(id) from objects" );

    # fire four beams at the light cruizer with health of 21. it should go down to 17 then heal 2 of those and be back at 19
    my $p1_fail = [ "F $p3boat->{ID} 4 $p2cruiz->{ID}",
		    "F $no_id 4 $p2cruiz->{ID}",
	];
    my $p1_fail_msg = [ "not found",
			"not found" ];
    $p1->set_next_state( 'orders', $p1_fail );

    my $p2_fail_a = [ "F $p2cruiz->{ID} 1 $no_id",
		      "F $p2c2->{ID} 1 $p2sc->{ID}",
		      "F $p2c2->{ID} 1 $p3boat->{ID}",
	];
    my $p2_succ = [ "F $p2cruiz->{ID} 1 $p3boat->{ID}",
		    "F $p2cruiz->{ID} 1 $p3boat->{ID}",
		    "F $p2cruiz->{ID} 1 $p3boat->{ID}",
	];
    my $p2_fail_b = [ "F $p2cruiz->{ID} 1 $p3scout->{ID}" ];
    my $p2_fail_msg = [ "not found",
			"your own ship",
			"not in same location",
			"out of targets"
	];
    
    $p2->set_next_state( 'orders', [ @$p2_fail_a, @$p2_succ, @$p2_fail_b ] );

    my $p3_succ = [ "F $p3boat->{ID} 4 $p2cruiz->{ID}" ];
    $p3->set_next_state( 'orders', $p3_succ );

    $g->advance_turn();

    check_messages( $p1, [], $p1_fail, $p1_fail_msg );
    check_messages( $p2, $p2_succ, [@$p2_fail_a,@$p2_fail_b], $p2_fail_msg );
    check_messages( $p3, $p3_succ );

    # check for running out of firepower
    check( 'damage to cruizer', $p2cruiz->get_state('health'), 19 );


    # test - continue to repair light cruizer, and have light cruizer
    #        destory the boat of player 2

    $p2->set_next_state( 'orders', ["F $p2cruiz->{ID} 8 $p3boat->{ID}"
                    ] );

    $g->advance_turn();
    check_messages( $p2, ["F $p2cruiz->{ID} 8 $p3boat->{ID}"]);
    
    check( 'healed up cruizer that is healed', $p2cruiz->get_state('health'), 21 );    
    check( 'destroyed boat', $p3boat->get_state('dead'), 1 );
    my $p3mess = $p3->get_state( 'messages' );
    my $p2mess = $p2->get_state( 'messages' );
    check_messages( $p3, [], [], [], ['fired on a3','results destroyed'] );
    check_messages( $p2, ["F $p2cruiz->{ID} 8 $p3boat->{ID}"], [], [], ['was destroyed' ] );

    # check that dead boat can't do anything.

    $g->advance_turn();
    check( 'healed up cruizer', $p2cruiz->get_state('health'), 21 );

} #fire

sub rename {
    my $self = shift;
    my ( $a1, $a2, $a3, $g ) = ( $self->{a1},$self->{a2},$self->{a3},$self->{g} );
    my $sectors = $self->{sectors};

    my $players = $g->get_players();
    my $p1 = $players->{$a1->{ID}};
    my $p2 = $players->{$a2->{ID}};
    my $s3_id = $sectors->[3]{ID};
    
    my( $p1ship ) = @{ $p1->get_state('ships') };
    my( $p2ship ) = @{ $p2->get_state('ships') };
    my( $no_id ) = G::Base::query_line( "select 2* max(id) from objects" );

    my $p1_succ = [ "N $p1ship->{ID} zoork woot" ];
    my $p1_fail = [ "N $p2ship->{ID} ama no",
                    "N $s3_id not my sector",
                    "N $no_id nonexistant",
        ];
    my $p1_fail_msg = [ 'not found',
                        'not found',
                        'not found',
                        'not found' ];
    $p1->set_next_state('orders', [ @$p1_succ, @$p1_fail ] );

    $g->advance_turn();

    check( 'turn', $g->get_turn(), 3 );
    check_messages( $p1, $p1_succ, $p1_fail, $p1_fail_msg );
    
} #rename

sub build {
    my $self = shift;

    my ( $a1, $a2, $a3, $g ) = ( $self->{a1},$self->{a2},$self->{a3},$self->{g} );
    my $sectors = $self->{sectors};
    my $players = $g->get_players();

    my $p1 = $players->{$a1->{ID}};
    my $p2 = $players->{$a2->{ID}};
    my $p3 = $players->{$a3->{ID}};

    my $s1_id = $sectors->[0]{ID};
    my $s2_id = $sectors->[1]{ID};
    my $s3_id = $sectors->[3]{ID};
    my $s5_id = $sectors->[5]{ID};
    my $s6_id = $sectors->[6]{ID};

    my $s8_id = $sectors->[8]{ID};
    my $s9_id = $sectors->[9]{ID};

    my( $no_id ) = G::Base::query_line( "select 2*max(id) from objects" );
    my $p1_succeed = [
        "B $s1_id 1 tasty", #scout
        "B $s1_id 9", #industry
        ];
    my $p1_fail = [
        "B $s1_id 11", #gunship, should fail for tech
        "B $s1_id 3 no go", #destroyer, not enough rus to build
        "B $s2_id 2 derp", #patrol boat, not enough size to build there
        "B $s5_id 1 cantbuildhere", #scout built on someone elses turf.
        "B $s3_id 1 cantbuildhere", #scout built on someone elses turf.
        "B $no_id 1 cantbuildnowhere", #scout built on nonexistant sector
        ];
    my $p1_fail_msg = [
        'tech level',
        'enough rus',
        'production',
        'not owned',
        'not owned',
        'exist',
        ];

    $p1->set_next_state('orders',[@$p1_succeed,
                                  @$p1_fail,
                        ] );
    #build cost of scout + industry is 5 + 3 = 8. 25 - 8 + (11+2) = 30
    my $p2_succeed = ["B $s5_id 10", #tech lvl 2
                             "B $s5_id 18", #tech lvl 3
                             "B $s5_id 19 croozer 1", #tech level 3 cruiser
                             "B $s5_id 19 croozer 2", #tech level 3 cruiser
                             "B $s5_id 1 scout", #scout
                             "B $s5_id 11 gunbt", #gunboat
                             "B $s6_id 9", #industry
                             "B $s6_id 9", #industry
        ];
    my $p2_fail = [ "B $s6_id 9", #industry build beyond max
        ];
    my $p2_fail_msg = [ "at max", #industry build beyond max
        ];
    $p2->set_next_state('orders', [@$p2_succeed,
                              @$p2_fail,
                   ]  );
    my $p3_succeed = [ "B $s8_id 1", #scout
                       "B $s8_id 2", #pat boat
        ];
    $p3->set_next_state('orders', $p3_succeed );
    $g->advance_turn();

    check( 'turn', $g->get_turn(), 2 );

    check_messages( $p1, $p1_succeed, $p1_fail, $p1_fail_msg );
    check_messages( $p2, $p2_succeed, $p2_fail, $p2_fail_msg );
    check_messages( $p3, $p3_succeed );

    check( 'rus after build', $p1->get_state('rus'),30);
    check( 'buildcap after prod', $sectors->[0]->get_state('buildcap'), 33 );

    my $sec_ships = $sectors->[0]->get_state('ships');

    check( 'ship count in sector', scalar( @$sec_ships ), 1 );
    check( 'ship name', $sec_ships->[0]->get_state('name'), 'tasty' );

    my $p_ships = $p1->get_state('ships');
    check( 'ship count in player', scalar( @$p_ships ), 1 );
    check( 'ship same in sector and player', $sec_ships->[0], $p_ships->[0] );
    check( 'production increase', $sectors->[0]->get_state('currprod'),11 );
    check( 'build capacity increase', $sectors->[0]->get_state('buildcap'),33 );
    check( 'ship name', $p_ships->[0]->get_state('name'), 'tasty' );

    my $sec_ships = $sectors->[5]->get_state('ships');

    check( 'ship count in sector', scalar( @$sec_ships ), 4 );
    check( 'ship name', $sec_ships->[1]->get_state('name'), 'croozer 2' );

} #build

sub check {
    my( $test, $has, $wants ) = @_;
    if( $has ne $wants ) {
        fail( "$test : Got $has and wants $wants" );
    } else {
        pass( "$test : value is $wants" );
    }
}

sub fail {
    my $msg = shift;
    print "Failed : $msg\n";
    exit(0);
}

sub pass {
    my $msg = shift;
    print "Passed : $msg\n";
}

sub check_state {
    my( $obj, $field, $state ) = @_;
    if( $obj->get_state($field) eq $state ) {
        pass( "state $field = $state" );
    } else {
        fail( "state $field. Was '".$obj->get_state($field)."' and was expecting '$state'" );
    }
}

sub check_messages {
    my $player = shift;
    my $s_list = shift;
    my $f_list = shift;
    my $f_msg  = shift;
    my $o_msg  = shift;
    my $tags   = shift || [];

    my $msgs = $player->get_state('messages');

    my( %cmd2succ, %cmd2fail, @observe );
    my $total_succ = 0;

    for my $msg (@$msgs) {
        if( $msg->{type} eq 'command' ) {
            if( $msg->{result} eq 'success' ) {
                $cmd2succ{$msg->{command}}++;
                $total_succ++;
            } else {
                push( @{$cmd2fail{$msg->{command}}}, $msg->{err} );
            }
        } else {
            my $name = ref( $msg->{target} ) =~ /^G/ ? $msg->{target}->namestr() : '?';
            push( @observe, join(' ',join(',',map { $_ } @{$msg->{actors}||[]}),$msg->{action},$name,'with results',$msg->{msg} ) );
        }
    }

    for my $cmd (@$s_list) {
	my $tag = shift @$tags;
        if( $cmd =~ /^\s*[NB]/ ) {
            my( $a, $where, $id, @name );
            if( $cmd =~ /\s*B/ ) {
                ( $a, $where, $id, @name ) = split(/\s+/,$cmd);
                $cmd = "$a $where $id";
            } else {
                ( $a, $id, @name )  = split(/\s+/,$cmd);
                $cmd = "$a $id";
            }
            if( @name ) {
                $cmd .= " ".join(' ',@name);
            }
        }

        if( $cmd2succ{$cmd} ) {
            pass( " $cmd : $tag" );
            $cmd2succ{$cmd}--;
            $total_succ--;
        } else {
            my $err = shift @{$cmd2fail{$cmd}};
            fail( $cmd.' : '.$player->get_name()." : $err : $tag" );
        }
    }

    if( $f_list && @$f_list ) {
        for my $i (0..$#$f_list) {
	    my $tag = shift @$tags;
            my( $fcmd, $ferr ) = ( $f_list->[$i], $f_msg->[$i] );
            if( $fcmd =~ /^\s*[NB]/ ) {
                my( $a, $where, $id, @name );
                if( $fcmd =~ /\s*B/ ) {
                    ( $a, $where, $id, @name ) = split(/\s+/,$fcmd);
                    $fcmd = "$a $where $id";
                } else {
                    ( $a, $id, @name )  = split(/\s+/,$fcmd);
                    $fcmd = "$a $id";
                }
                if( @name ) {
                    $fcmd .= " ".join(' ',@name);
                }
            }
            my $fails = $cmd2fail{$fcmd};
            if( $fails && @$fails ) {
                my $rerr = shift @$fails;
                if( $rerr =~ /$ferr/i ) {
                    pass( "$fcmd Failed with message '$rerr' and expecting '$ferr' : $tag" );
                } else {
                    fail( "Expected to fail : $fcmd :  with error '$ferr' and got '$rerr' : $tag" );
                }
            } else {
                fail( "Expected to fail : $fcmd : $tag" );
            }
        }
    }
    
    if( $o_msg && @$o_msg ) {
	for my $i (0..$#observe) {
	    my $tag = shift @$tags;
	    if( $observe[$i] =~ /$o_msg->[$i]/ ) {
		pass( $player->get_name()." : $observe[$i] : $tag" );
	    } else {
		fail( $player->get_name()." : got '$observe[$i]' expected '$o_msg->[$i]' : $tag" );
	    }
	}
    }
    
    if( $total_succ != 0 ) {
        fail( $player->get_name()." : $total_succ more successes seen then are looking for" );
    }
    
} #check_messages

sub check_message {
    my( $test, $messages, $index, $succeed, $failmsg ) = @_;
    my $msg = $messages->[$index];
    if( $succeed  ) {
        if( $msg =~ /^S/ ) {
            pass( "$test with message '$msg'" );
        } elsif( $succeed == 2 ) {
            if( $msg =~ /^I.*$failmsg/ ) {
                pass( " $test with message '$msg'" );
            } else {
                fail( "$test : Expected info and got '$msg'" );
            }
        }
        else {
            fail( "$test : Expected to succeed and message was '$msg'" );
        }
    } 
    else { #fail case
        if( $msg =~ /^F.*$failmsg/i ) {
            pass( " $test with message '$msg'" );
        } else {
            fail( " $test : Expected to fail with text '$failmsg' and message was '$msg'" );
        }
    }
} #check_message

sub set_up {
    my $self = shift;

    my $g = new SE::StellarExpanse();
    $g->set_flavor( $g->new_flavor() );
    my $a1 = new G::Account();
    $a1->set_name("a1");
    my $p1 = $g->add_player($a1);

    $self->{p1} = $p1;
    $g->add_to_state_items( $p1 );

    my $a2 = new G::Account();
    $a2->set_name("a2");
    my $p2 = $g->add_player($a2);
    $g->add_to_state_items( $p2 );

    my $a3 = new G::Account();
    $a3->set_name("a3");
    my $p3 = $g->add_player($a3);
    $g->add_to_state_items( $p3 );
    my( @sectors );
    for my $i (0..10) {
        my $s = new SE::Sector();
        $s->set_game( $g );
        $s->set_state( 'name', "Sector $i" );
        $g->add_to_state_items( $s );
        $s->set_maxprod( 4 );
        $s->set_state( 'currprod', 0 );
        $s->set_state( 'buildcap', 0 );
        $g->add_to_sectors( $s );
        push @sectors, $s;
        if( $i ) {
            $s->link_sectors( $sectors[$i-1] );
        }
    }
    $self->{sectors} = \@sectors;
    #set up for each player. create planet and owned system
    $p1->add_to_state( 'systems', $sectors[0] );
    $p1->add_to_state( 'systems', $sectors[1] );
    $p1->set_state('maps', {} );

    $sectors[0]->set_state( 'owner',  $p1 );

    $sectors[1]->set_state( 'owner',  $p1 );
    $sectors[0]->set_state( 'name', "p1 prime" );
    $sectors[0]->set_maxprod( 25 );
    $sectors[0]->set_state( 'currprod', 10 );
    $sectors[0]->set_state( 'buildcap', 30 );
    $sectors[1]->set_maxprod( 9 );
    $sectors[1]->set_state( 'currprod', 2 );
    $sectors[1]->set_state( 'buildcap', 6 );

    $p2->add_to_state( 'systems', $sectors[5] );
    $p2->add_to_state( 'systems', $sectors[6] );
    $p2->set_state('maps', {} );
    $sectors[5]->set_state( 'owner',  $p2 );
    $sectors[6]->set_state( 'owner',  $p2 );
    $sectors[5]->set_maxprod( 25 );
    $sectors[5]->set_state( 'currprod', 10 );
    $sectors[5]->set_state( 'buildcap', 30 );
    $sectors[6]->set_maxprod( 9 );
    $sectors[6]->set_state( 'currprod', 7 );
    $sectors[6]->set_state( 'buildcap', 9 );

    $p3->add_to_state( 'systems', $sectors[8] );
    $p3->add_to_state( 'systems', $sectors[9] );
    $p3->set_state('maps', {} );
    $sectors[8]->set_state( 'owner',  $p3 );
    $sectors[9]->set_state( 'owner',  $p3 );
    $sectors[8]->set_maxprod( 25 );
    $sectors[8]->set_state( 'currprod', 10 );
    $sectors[8]->set_state('buildcap', 30 );
    $sectors[9]->set_maxprod( 9 );
    $sectors[9]->set_state( 'currprod', 8 );
    $sectors[9]->set_state( 'buildcap', 24 );
    
    $g->advance_state();
    $g->set_prototypes( $g->get_flavor() );
    $self->{g} = $g;
    $self->{a1} = $a1;
    $self->{a2} = $a2;
    $self->{a3} = $a3;

    $p1->set_state( 'tech', 1 );
    $p1->set_state( 'rus', 25 );

    $p2->set_state( 'tech', 2 );
    $p2->set_state( 'rus', 525 );
    
    $p3->set_state( 'tech', 3 );
    $p3->set_state( 'rus', 125 );

} #set_up


1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut
