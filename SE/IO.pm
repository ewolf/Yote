package G::ARCADE::StellarExpanse::IO;

use strict;

use lib '/home/wolf/proj';

use Data::Dumper;

use G::GameHangar;
use G::ARCADE::StellarExpanse::StellarExpanse;

use Carp qw/confess/;

#
# Treat process data as if its a form handler. In a sence, it is, even though its being
# called on a server called from a webserver.
#
sub process_data {
    my $form = shift;


    # process cases :
    #   no credentials 
    #      -> supply intro/splash/login screen
    #   creating account
    #      -> no credientials supplied, go to creation page
    #      -> failes unique usernmae or email check, go to creation page with message
    #      -> create account and go to lobby
    #   wrong credentials
    #      ->  login error with options to make account, log in again, or go back to intro screen
    #   correct credentials
    #     no game specified
    #        -> lobby, list of games that can be joined or continued (play)
    #     game to join
    #        -> if game has spots open, join the game and play it
    #        -> if game doesn't have spots open, go back to lobby with message
    #     game to play
    #        -> if game is over, go back to lobby with message
    #        -> if not joined game, go back to lobby with message
    #        -> if you have joined it, go to this game
    my( $session, $uname, $email, $password ) = @$form{'session','uname','email','password'};
    if( $form->{create_account} ) {
	if( $uname && $password ) {
	    my $H = G::GameHangar::get_hangar();
	    if( $H->account_taken( $uname, $email ) ) {
		return create_account( $uname, $email, $password, 'Email or Username taken' );
	    } else {
		$H->create_account( $uname, $password );
		return lobby( $form );
	    }
	} else {
	    return create_account();
	}
    }
    elsif( $form->{uname} ) {
	my $H = G::GameHangar::get_hangar();
	
    } else {
	#no credentials
	return intro( $form );
    }
    
    
    my $H = G::GameHangar::get_hangar();

    if( $form->{a} eq 'create_account' ) {
        my( $name, $pw, $em ) = ( $form->{uname}, $form->{pword}, $form->{email} );
        $name =~ s/^\s*//;
        $name =~ s/\s*$//;
        $pw =~ s/^\s*//;
        $pw =~ s/\s*$//;
        $em =~ s/^\s*//;
        $em =~ s/\s*$//;
        if( $name && $pw && $em ) {
            if( $H->account_taken( $name, $em ) ) {
                $res = { err => "Handle or Email already taken" };
            } else {
                my $instances = $H->get_game_instances('G::ARCADE::StellarExpanse::StellarExpanse');
                $H->create_account( $name, $pw, $em );
                my( $acct, $sess ) = $H->login( $form );
                $res = {  
                    uname    => $acct->get_name(),
                    session => $sess,
                    acct    => $acct->{ID},
                    joined  => [],
                    can_join => [map { game_to_data( $_ ) } grep { $_->can_join() } @$instances],
                };
            } 
            
        } else {
            $res = { err => "Missing username or password" };
        }           
    } else {
        my( $acct, $session ) = $H->login( $form );
        if( $session ) {
            if( $form->{a} eq 'login' ) {
                my $instances = $H->get_game_instances('G::ARCADE::StellarExpanse::StellarExpanse');
                # joined games,  available games
                my( @joined, @can_join );
                for my $game (@$instances) {
                    my $gdata = game_to_data( $game );
                    my $players = $game->get_players({});
                    if( $players->{$acct->{ID}} ) {
                        push( @joined, $gdata );
                    } elsif( $game->can_join() ) {
                        push( @can_join, $gdata );
                    }
                }
                $res = { 
                    acct     => $acct->{ID},
                    uname    => $acct->get_name(),
                    session  => $session,
                    joined   => \@joined,
                    can_join => \@can_join,
                };
            } elsif( $form->{a} eq 'logout' ) {
                $H->logout( $form );
                $res = { msg => 'logged out' };
            } elsif( $form->{a} eq 'checkgame' ) {
                my $game = G::Base::fetch( $form->{game} );
                if( $game ) {
                    my $players = $game->get_players({});
                    $res = { turn => $game->get_turn() || 0,
                             player_ready => [ map { { ready => $_->get_state( 'ready' ) } } 
                                               sort { lc( $a->get_name() ) cmp lc( $b->get_name() ) }
                                               (values %$players) ],
                    };
                }
		$res->{session} = $session;
	    } elsif( $form->{a} eq 'gmessage' ) {
		my $game = G::Base::fetch( $form->{game} );
                if( $game ) {
                    my $game_players = $game->get_players({});
                    my $player = $game_players->{$acct->{ID}};
		    my( $recip ) = ( grep { $_->{ID} == $form->{recip} } values %$game_players );
		    if( $recip ) {
			my $talk = $form->{msg};
			my $my_talk = $player->get_talk({});
			my $talks = $recip->get_talk({});
			push( @{$talks->{$player->{ID}}}, $player->get_name(). "> $talk" );
			push( @{$my_talk->{$recip->{ID}}},$player->get_name(). "> $talk" );
			if( scalar( @{$talks->{$player->{ID}}} ) > 50 ) {
			    shift @{$talks->{$player->{ID}}};
			}
			$res = { talks => $my_talk };
		    } else {
			$res = { err => "unknown recipient" };
		    }
		}	
		$res->{session} = $session;	
            } elsif( $form->{a} eq 'join' ) {
                my $game = G::Base::fetch( $form->{game} );
                if( $game ) { #game exists to join
                    my $game_players = $game->get_players({});
                    my $player = $game_players->{$acct->{ID}};
                    my $just_joined = 0;
                    if( ! $player ) { # is not joined allready
                        if( $game->can_join() ) { #is able to join
                            $player = $game->add_player( $acct );
                            $just_joined = 1;
                            if( $game->get_game_state() eq $G::Game::READY ) { #start the game
                                $game->start();
                            }
                        }
                    }
                    if( $game->get_game_state() eq $G::Game::IN_PROGRESS ) {
                        if( $player ) { #joined a game in progress they belonged to
                            my $data = full_data( $player, $game, game_to_data( $game ) );
                            $data->{ready} = $player->get_state('ready');
                            $data->{session} = $session;
                            my $acct = $player->get_account();
                            $data->{uname} = $acct->get_name();
                            $res = $data;
                        } else { #tried to join a game in progress that they didnt belong to
                            $res = { msg => "Could not join" };
                        }
                    } else {
                        if( $just_joined ) {
                            $res = { msg => "Joined game. The game will start when all players have joined." };
                        } else {
                            $res = { msg => "Game is not yet in progress" };
                        }
                    }
		    $res->{session} = $session;
                }
            } elsif( $form->{a} eq 'gen_comm' ) {
                my $others = G::Base::get_arows("SELECT account_id FROM session WHERE last_connected >= now() - INTERVAL 15 minute AND account_id != ? ORDER by last_connected DESC", [ $acct->{ID} ] );
                $res = [ session => $session, map { {id => $_->{ID}, name => $_->get_name() } } map { G::Base::fetch($_->[0]) } @$others];
            } elsif( $form->{a} eq 'game_comm' ) {
                my $game = G::Base::fetch( $form->{game} );
                if( $game ) {
                    my $game_players = $game->get_players({});
                    my $player = $game_players->{$acct->{ID}};
                    $res = [ map { {
                        id   => $_->{ID}, 
                        session => $session,
                        name => $_->get_name() } } 
                             sort { lc($a->get_name()) cmp lc($b->get_name()) } 
                             grep { $_->{ID} != $player->{ID} } values %$game_players];
                }	    
            } elsif( $form->{a} eq 'deletegame' ) {
                my $game = G::Base::fetch( $form->{game_id} );
                if( $game->get_created_by()->{ID} == $acct->{ID} ) {
		    $game->delete();
                    $res = { msg => "Deleted" };
		    $res->{session} = $session;
                } else {
                    $res = { err => "Only the game creator can delete" };
                }
            } elsif( $form->{a} eq 'editgame' ) {            
                my $instances = $H->get_game_instances('G::ARCADE::StellarExpanse::StellarExpanse');
                if( $form->{data} ) {
                    my $game = G::Base::fetch( $form->{game_id} );
                    for my $key (qw/name number_players starting_resources starting_tech_level starting_sectors/) {
                        $game->set( $key, $form->{$key} );
                    }
                }
                $res = editing_game( $form->{game_id} );
		$res->{session} = $session;
            } #editgame
	    elsif( $form->{a} eq 'newgame' ) {
                my $class = 'G::ARCADE::StellarExpanse::StellarExpanse';
                my $flavors = $class->flavors();
                my( $flav ) = (@$flavors);
		eval "use $class;";
                my $game = $class->new();
                $game->set_flavor( $flav );
                $game->set_game_state( $G::Game::CONFIGURING );
                $game->set_name( $acct->get_name()." game" );
                $game->set_created_by( $acct );
                
                $game->set_number_players( 5 );
                $game->set_starting_resources( 25 );
                $game->set_starting_sectors( 100 );
                $game->set_starting_tech_level( 1 );
                my $game_id = $game->{ID};
                $acct->add_to_created_games($game);
                my $insts = $H->get_game_instances($class);
		print STDERR "Adding to $insts\n";
                push( @$insts, $game );	    
                $res = editing_game( $game_id );
		$res->{session} = $session;
                $res->{msg} = "new game created";
            } #newgame 
	    elsif( $form->{a} eq 'update_game_comm' ) {
                my $game = G::Base::fetch( $form->{game} );
                my $players = $game->get_players({});
                my $player = $players->{$acct->{ID}};
		my $talks = $player->get_talk({});
		my %their_talks;
		for my $p (values %$players) {
		    my $ttalks = $p->get_talk({});
		    $their_talks{$p->{ID}} = $ttalks->{$player->{ID}};
		}
                $res = {
                    name => $game->get_name(),
                    turn => $game->get_turn() || 0,
                    tech => $player->get_state( 'tech' ),
		    player_id => $player->{ID},
                    rus  => $player->get_state( 'rus' ),
                    players => [map { {name    => $_->get_name(), 
				       id      => $_->{ID},
                                       ready   => $_->get_state( 'ready' ),
				       sending => $talks->{$player->{ID}}[0],
                                       msgs    => $their_talks{$_->{ID}},
			} }
                                sort { lc( $a->get_name() ) cmp lc( $b->get_name() ) }
#			    grep { $_->{ID} != $player->{ID} }
                                (values %$players)]
                };
                
                my $messages = $player->get_state( 'messages' );

                my( %sys2msg );
                for my $m (@$messages) {
                    my $msg = {};
                    for my $key (qw/err msg action result type/) {
                        $msg->{$key} = $m->{$key} if $m->{$key};
                    }
                    for my $key (qw/origin location destination actor target/) {
                        $msg->{$key} = $m->{$key}->namestr() if $m->{$key};
                        $msg->{"${key}_id"} = $m->{$key}->{ID} if $m->{$key};
                    }
                    push( @{$sys2msg{$msg->{location_id}||$msg->{destination_id}||'general'}}, $msg );
                }
                for my $sysid (sort keys %sys2msg) {
                    my $msgs = $sys2msg{$sysid};
                    for my $msg (@$msgs) {
                        push( @{$res->{messages}},
                              { msg =>$msg->{msg}, 
				err => $msg->{err},
                                loc => $msg->{location}, 
                                loc_id => $msg->{location_id},
                                action => $msg->{action},
                              } );
                    }    
                }

            } #update_game_comm
	    elsif( $form->{a} eq 'orders' ) {
                my $game = G::Base::fetch( $form->{game} );
                if( $game ) {
		    print STDERR "Checking orders for $form->{turn} and game turn is ".$game->get_turn()."\n";
		    print STDERR Data::Dumper->Dump( [$form] );
                    if( $form->{turn} == $game->get_turn() ) {
                        my $game_players = $game->get_players({});
                        my $player = $game_players->{$acct->{ID}};
                        my( @ord_keys ) = grep { /^ORD_/ } keys %$form;
                        if( $form->{set_ready} ) {
                            $player->set_state( 'ready', 1 );
                        } else {
                            $player->set_state( 'ready', 0 );
                        }

                        my( @ords );

                        my( @SCOUT ) = grep { /^ORD_SM_/ } @ord_keys;
                        my( %sid2idx );
                        for my $s (@SCOUT) {
                            if( $s =~ /^ORD_SM_(\d+)_(\d+)/ ) {
                                $sid2idx{$1}{$2} = $form->{$s} if $form->{$s} ne 'none';
                            }
                        }

                        for my $sid (keys %sid2idx) {
                            my( @idx ) = sort { $a <=> $b } keys %{$sid2idx{$sid}};
                            for my $idx (@idx) {
                                my $sys = $form->{"ORD_SM_${sid}_$idx"};
                                push( @ords, "M $sid $sys" );
                            }
                        }

                        for my $orda (@ord_keys) {
                            next if $orda =~ /^ORD_SM_/; #already did scout moves
                            if( $orda =~ /^ORD_BSS_(\d+)_(\d+)/ ) { #build
                                my( $system, $idx ) = ( $1, $2 );
                                my $buildwhat = $form->{$orda};
                                if( $buildwhat && $buildwhat > 0 ) {
                                    my $buildname = $form->{"ORD_BSN_${system}_$idx"};
                                    $buildname =~ s/[\'\"]/_/gs;
                                    for my $bid (1..$form->{"ORD_BSQ_${system}_$idx"}) {
                                        my $thisbm = $buildname;
                                        $thisbm .= " $bid" if $buildname;
                                        push( @ords, "B $system $buildwhat $thisbm" );
                                    }
                                }
                            } elsif( $orda =~ /^ORD_PM_(\d+)/ ) { #path move
				if( $form->{$orda} && $form->{$orda} ne 'none' ) {
				    my $ship = G::Base::fetch( $1 );
				    my $loc = $ship->get_state( 'location' );
				    my $dest = G::Base::fetch( $form->{$orda} );
				    my $path = shortest( $loc, $dest, $ship->get_prototype('jumps') ) || [];
				    print STDERR "Move order for ship ".$ship->namestr()." from ".$loc->namestr()." to dest ".$dest->namestr()." and got a path of ".join(',',@$path).", and remaining move of ".$ship->get_state('remaining_move')."\n";

				    for my $p (@$path) {
					push( @ords, "M $ship->{ID} $p->{ID}" );
				    }
				}
                            } elsif( $orda =~ /^ORD_ST_(\d+)_(\d+)/ ) { #fire
                                my( $shipid, $idx ) = ( $1, $2 );
                                push( @ords, "F $shipid ".$form->{"ORD_SS_${shipid}_$idx"}." ".$form->{$orda} ) if $form->{"ORD_SS_${shipid}_$idx"} > 0;
                            } elsif( $orda =~ /^ORD_REN_(\d+)/ ) { #rename
                                my $id = $1;
                                if( $form->{"HORD_REN_$id"} ne $form->{$orda} ) {
                                    push( @ords, "N $id $form->{$orda}" );
                                }
                            } elsif( $orda =~ /^ORD_RE_(\d+)/) { #repair
                                my $cid = $1;
                                $form->{$orda} =~ s/[\"\']/_/gs;
                                push( @ords, "R $cid $form->{$orda}" ) if $form->{$orda} > 0;
                            } elsif( $orda =~ /^ORD_LO_(\d+)/) { #load
                                my $id = $1;
                                my( @ids ) = split( /\0/, $form->{$orda} );
                                push( @ords, map { "L $_ $id" } @ids );
                            } elsif( $orda =~ /^ORD_UL_(\d+)/ ) { #unload
                                my $id = $1;
                                push( @ords, "U $id" );	    
                            }
                        } #each order
                        push( @ords, split(/[\n\r]+/s,$form->{ORD_ADDITIONAL} ) ) if $form->{ORD_ADDITIONAL};

			print STDERR "For turn ".$player->get_turn()." + 1. Setting orders for player '".$player->namestr()."' : ".join( ' , ', map { "'$_'" } @ords)."\n";
                        
                        # Check existing orders
                        if( @ords ) {
                            $player->set_next_state( 'orders', [@ords] );
                        }
                        if( $form->{set_ready} && $form->{turn} == $game->get_turn() ) {
                            $player->set_state( 'ready', 1 );
                        }

                        # check to see if the turn advanced.
                        if( $game->players_are_ready() ) {
			    print STDERR "Game ".$game->namestr()." advancing turn from ".$game->get_turn()."\n";
                            $game->advance_turn();
			    print STDERR "Game ".$game->namestr()." now on turn  ".$game->get_turn()."\n";
			    my $gname = $game->get_name();
			    if( ! $game->verify_map() ) {
#				`echo "Game $gname ($game->{ID}) has failed map" | mail -s 'Game $gname failed on map' coyocanid\@gmail.com`;
			    }
                            $res = { msg => "advanced turn to ". $game->get_turn(), 
                                     session => $session,
                                     turn_happened => 1,
                            };
			    my $players = $game->get_players();


			    for my $p (values %$players) {
				my $email = $p->get_account()->get_email();
				eval {
#				    `echo "Game $gname is ready for the next turn" | mail -s 'Game $gname is ready for the next turn' $email`;
				};
			    }
                        } #players are ready
			else {
                            $res = { 
                                ready => $player->get_state('ready'),
                                gameready => $game->players_are_ready(),
                                session => $session,
                                msg => "orders submitted $@ $!".Data::Dumper->Dump([\@ords])};
                        }

                    } #if the turn is correct 
		    else {
                        $res = { session => $session, msg => 'orders submitted for previous turn' };
                    }
                } #if there is a game
		else {
                    $res = { msg => 'nada game' };
                }
            } #if orders
        } #able to log in 
        else {
            $res = { err => 'Unable to log in with those credentials', form=>Data::Dumper->Dump([$form]) };
        }    
    } # not creating account
    return $res;
} #main

sub full_data {
    my( $player, $game, $data ) = @_;

    my $rus = $player->get_state( 'rus' );
    my $tech = $player->get_state( 'tech' );
    my $maps = $player->get_state( 'maps' );

    $data->{rus} = $rus;
    $data->{tech} = $tech;

    my $murl = "StellarExpanse/data/maps/$game->{ID}/".$game->get_turn()."/$player->{ID}";
    my $mapurl = "$ENV{YOTE_ROOT}/$murl.png";
#    my $mapurl = "http://dev.pandamonkey.com/~wolf/game/$murl.png";
#    my $mapurl = "/ac/$murl.png";

    my $jsurl = "$murl.js";
    my $res = open( IN, "<$ENV{GLIB}/G/ARCADE/$jsurl") or die "$! $ENV{GLIB}/G/ARCADE/$jsurl";

    my $js = '';
    while(<IN>) { $js .= $_; }
    close IN;
    $data->{mapurl} = $mapurl;
    $data->{jsurl} = $jsurl;
    $data->{js} = $js;

    my $orders = $player->get_next_state( 'orders', [] );
    my( %renames, %builds, %fires, %moveto, %pathmove, %unload, %load, %repairs );
    my( %quanbuild );
    for my $o (@$orders) {
        # rename
        if( $o =~ /^\s*N\s+(\d+)\s+(.*)/ ) {
            $renames{$1} = $2;
        } 
        # build
        elsif( $o =~ /^\s*B\s+(\d+)\s+(\d+)(\s+(.*))?/ ) {
            my( $system, $item, $name ) = ( $1, $2, $4 );
            $name =~ s/(.*)\d+\s*$/$1/;
            my $build = $quanbuild{$system}{$item}{$name};
            if( ! $build ) {
                $build = { item => $item, name => $name };
                $quanbuild{$system}{$item}{$name} = $build;
                push( @{$builds{$system}}, $build );
            }
            $build->{quan}++;
        } #build
        #fire
        elsif( $o =~ /^\s*F\s+(\d+)\s+(\d+)\s+(\d+)/ ) { # F source amount target
            my( $sid, $amt, $targ ) = ( $1, $2, $3 );
            my $ship = G::Base::fetch( $sid );
            my $loc = $ship->get_state( 'location' );
            push( @{$fires{$ship->{ID}}}, { target => $targ, amount => $amt } );
        } #fire
        elsif( $o =~ /^\s*M\s+(\d+)\s+(\d+)/ ) { # F source amount target
            my( $sid, $destid ) = ( $1, $2 );
            my $dest =  G::Base::fetch( $destid );
            $moveto{$sid} = $destid; #the last one in the chain of moves should be the destination
            push( @{$pathmove{$sid}}, { id => $destid, name => $dest->namestr() } );
        }
        elsif( $o =~ /^\S*R\s+(\d+)\s+(\d+)/ ) {
            $repairs{$1} = $2;
        }
        elsif( $o =~ /^\s*U\s+(\d+)/ ) {
            $unload{$1} = 1;
        }
        elsif( $o =~ /^\s*L\s+(\d+)\s+(\d+)/ ) {
            push( @{$load{$1}}, $2 );
        }
    }
    
    my( %seen );
    for my $pid (keys %$maps) {
        my $node = $maps->{$pid};
        my $sect = $node->get_system();
        my $own  = $sect->get_state( 'owner' );
        my $ship = $sect->get_state( 'ships', [] );

        my $links = $sect->get_links();
        my( @link_data );
        for my $l (values %$links) {
            next if $seen{$l->{ID}};
            $seen{$l->{ID}} = 1;
            if( ! $maps->{$l->{ID}} ) {
                $data->{system}{$l->{ID}} = {
                    id      => $l->{ID},
                    namestr => $l->namestr(),
                    name    => $l->get_state('name'),
                    unseen  => 1,
                    their_ships => [],
                    my_ships => [],
                };
            }
        }

        my $rename = $sect->get_state( 'name');

        my $title2id = $game->get_flavor()->get_prototypes();
        my $planetId2info = { name => $sect->get_state( 'name' ) };

        my $node = $maps->{$pid};
#	my $oships = $maps->get_state( 'their_ships', [] );
#	$planet
        my( @can_build_size ) = grep { $_->get_cost() <= $rus } grep { $_->get_size() <= $sect->get_state( 'buildcap' ) } (values %$title2id);
        my( $build_tech ) = grep { $_->get_tech_level() == $tech } grep { $_->get_type() eq 'TECH' } (@can_build_size);
        if( $build_tech && $rus > $build_tech->get_cost() ) {
            my $max_more = $rus - $build_tech->get_cost();
            ( @can_build_size ) = grep { $_->get_cost() <= $max_more || $_->get_tech_level() <= $tech } grep { ($_->get_tech_level() - 1) <= $tech } (@can_build_size);
        } else {
            ( @can_build_size ) = grep { $_->get_tech_level() <= $tech } (@can_build_size);
        }
        
        ( @can_build_size ) = grep { ! ($_->get_type_level() eq 'TECH' && $_->get_tech_level() < $tech ) } (@can_build_size);
        if( $sect->get_maxprod() == $sect->get_state( 'currprod' ) ) {
            ( @can_build_size ) = grep { $_->get_type() ne 'IND' } (@can_build_size);
        }
        ( @can_build_size ) = sort { $a->get_design_id() <=> $b->get_design_id() }  (@can_build_size);
        
        my( @can_build ) = ( { name => 'None' } );
        for my $info (@can_build_size) {
            push( @can_build, {map { $_ => $info->get($_) }  (qw/name tech_level damage_control jumps design_id cost targets self_destruct attack_beams defense size racksize type/) } );
        }


        # ...  SHIPS ....

        my( @my_ships, @their_ships );
        for my $oship (@$ship) {
            if( $oship->get_state( 'owner' ) eq $player ) {
                push( @my_ships, $oship ) ;
            } else {
                push( @their_ships, $oship ) ;
            }
        }	

        my( @my_ship_data );
        for( my $idx=0; $idx<@my_ships; ++$idx ) {
            my $ship = $my_ships[$idx];
            my $sdata = ship_data( $ship );
            if( $sdata->{type} eq 'Scout' ) {
                $sdata->{pathmoves} = $pathmove{$ship->{ID}} || [];
                my $dests = find_within( $sect, $maps, $ship->get_prototype('jumps'), 1 );
                $sdata->{destinations} = [ { id => undef, name => 'none' }, map {{ id => $_->{ID}, name => $_->namestr()}} sort { lc($a->namestr()) cmp lc($b->namestr()) } @$dests ];
            } else {
                my $sect = $ship->get_state('location');
                my $mtargs = find_within( $sect, $maps, $ship->get_prototype('jumps') );
                $sdata->{destination} = $moveto{$ship->{ID}};
                $sdata->{endpoints} = [ { id => undef, name => 'none' }, map {{ id=>$_->{ID}, name =>$_->namestr()}} @$mtargs];
            }
            my $rackspace = $ship->get_state( 'free_rack' );
            if( $rackspace > 0 ) {
                my @loadable = map { { id => $_->{ID}, name => $_->namestr() } } grep { $_->get_prototype('size') <= $rackspace && ref( $_->get_state('location') ) eq 'G::ARCADE::StellarExpanse::Sector' } @my_ships;
                $sdata->{can_load} = \@loadable;
            }
            my $carried = $ship->get_state( 'carried' );
            $sdata->{carried} = [map { { id => $_->{ID}, name => $_->namestr() } } @$carried];
            $sdata->{repair} = $repairs{$ship->{ID}} || 0;
            $sdata->{rename} = $renames{$ship->{ID}} || $sdata->{name};
            $sdata->{load_ord} = $load{$ship->{ID}} || {};
            for( my $find=0; $find<$ship->get_prototype('targets'); $find++ ) {
                $sdata->{fire}[$find] = $fires{$ship->{ID}}[$find];
            }

            $sdata->{unload_ord} = { map { $_->{ID} => 1 } grep { $unload{$_->{ID}} } @$carried };
            push( @my_ship_data, $sdata );
        } #each my_ship
        my $s_data = {
            id       => $sect->{ID},
            namestr  => $sect->namestr(),
            name     => $sect->get_state( 'name'),
            rename   => $renames{$sect->{ID}} || $sect->get_state('name'),
            currprod => $sect->get_state( 'currprod' ),
            maxprod  => $sect->get_maxprod(),
            buildcap => $sect->get_state( 'buildcap' ),
            owner    => $own ? $own->get_name() : undef,
            am_owner => $own && $own->get_name() eq $player->get_name(),
            builds   => $builds{$sect->{ID}}||[],
            can_build => \@can_build,
            their_ships => [map { ship_data( $_ ) } @their_ships],
            my_ships => \@my_ship_data,
        };
        $data->{system}{$sect->{ID}} = $s_data;

#	$data->{debug} = 1;
    } #each pid

    $data->{o} = Data::Dumper->Dump([$orders]),

    return $data;
} #full_data

sub ship_data {
    my $ship = shift;
    my $res = {
        id => $ship->{ID},
        owner => $ship->get_state('owner')->get_name(),
        type => $ship->get_prototype( 'name' ),
        (map { $_ => $ship->get_state($_) }  (qw/name health/)),
        (map { $_ => $ship->get_prototype($_) }  (qw/tech_level damage_control jumps design_id cost targets self_destruct attack_beams defense size racksize/)),
    };
    return $res;
} #ship_data

sub game_to_data {
    my $game = shift;
    confess unless $game;
    my $data = { id => $game->{ID} };
    for my $key (qw/name game_state turn/) {
        $data->{$key} = $game->get( $key );
    }
    my $creator = $game->get_created_by();
    $data->{creator}{id} = $creator->{ID};
    $data->{creator}{name} = $creator->get_name();
    my $players = $game->get_players();
    $data->{players} = [ map { { name => $_->get_name(), 
				 id => $_->{ID},
				 ready => $_->get_state('ready'),
				 acct => $_->get_account()->{ID} } } grep { $_->get_account() } values %$players ];
    $data->{number_players} = $game->get_number_players();
    $data->{turn} => $game->get_turn();
    return $data;
} #game_to_data

sub editing_game {
    my $game_id = shift;
    my $game = G::Base::fetch( $game_id );
    return unless $game;
    my $res = { id => $game_id };
    for my $key (qw/number_players starting_resources starting_tech_level starting_sectors turn game_state name/) {
        $res->{$key} = $game->get( $key );
    }
    return $res;
} #editing_game

#
# Returns a list ref of the systems within the amount specified.
#
sub find_within {
    my( $start_sector, $maps, $within, $keep_origin ) = @_;

    return unless $within > 0;

    my( %res );
    my $touches = $start_sector->get_links();
    for my $t (values %$touches) {
        if( $within > 1 && $maps->{$t->{ID}} ) {
            my $more = find_within( $t, $maps, $within - 1, $keep_origin );
            for my $m (@$more) {
                $res{$m->{ID}} = $m;
            }
        } 
        $res{$t->{ID}} = $t;
    }

    $res{$start_sector->{ID}} = $start_sector;
    delete $res{$start_sector->{ID}} unless $keep_origin;
    return [values %res];
} #find_within


#finds a valid path from a to b within n tries or returns undef;
#returns the value as a list of ids, not including a.
sub shortest {
    my( $a, $b, $n ) = @_;
    return undef unless $n > 0;
    my $cons = $a->get_links();
    print STDERR "Shortest with connections from ".$a->namestr()." : ".join(',',map { "$_ -> $cons->{$_}" } keys %$cons)."\n";
    my( $c ) = grep { $b->{ID} == $_->{ID} } values %$cons;
    return [$c] if $c;

    if( $n == 1 ) {
        if( grep { $b->{ID} == $_->{ID} } values %$cons) {
            return [$b];
        } else {
            return undef;
        }
    }
    for my $c (values %$cons) {
        my $res = shortest( $c, $b, $n - 1 );
        if( $res ) {
            return [$c,@$res];
        }
    }
    return undef;
} #shortest

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut
