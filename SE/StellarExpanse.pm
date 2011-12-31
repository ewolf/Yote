package GServ::SE::StellarExpanse;

#
# Implementation attempt at the stellar expanse game.
#
# Summary of data. The game consists of players, systems and ships.
#

#
# Must enumerate the objects and their fields for handy reference.
#

use strict;

use GServ::SE::DefaultShips;
use GServ::SE::Group;
use GServ::SE::GlomGroup;
use GServ::SE::Player;
use GServ::SE::Sector;
use GServ::SE::Ship;

use Config::General;
use Cwd;

#use lib for GraphViz
use lib "/home1/irrespon/proj/lib/perl5/site_perl/5.8.8";
use GraphViz;

use base 'GServ::Obj';

#$ENV{PATH} .= ':/home1/irrespon/usr/local/bin/';

#
# This game can have multiple configurations.
#
sub flavors {
    my $pkg = shift;
    my $root = new GServ::Obj();
    my $se_root = $root->get_stellar_expanse( new GServ::Obj() );
    my $flavors = $se_root->get_game_flavors([]);
    if( @$flavors == 0 ) {
        my $flavor = new_flavor();
        push( @$flavors, $flavor );
    }

    return $flavors;
} #flavors

sub new_flavor {
    my $flav = new GServ::Obj();
    $flav->set_name( 'classic' );

#    my $maxkey = 0;
    my $ships = {};
    for my $key (keys %GServ::SE::DefaultShips::defaultships ) {
#        $maxkey = $key if $key > $maxkey;
        my $prot = new GServ::Obj();
        my $shipdata = $GServ::SE::DefaultShips::defaultships{$key};
        for my $dkey (keys %$shipdata) {
            $prot->set( $dkey, $shipdata->{$dkey} );
        }
        $ships->{$key} = $prot;
    }
#    $flav->set_maxkey( $maxkey );

    $flav->set_prototypes( $ships );

    return $flav;
} #new_flavor

# --------------------------------------------------

sub everyone_ready {
    my $self = shift;

    my $players = $self->get_players();
    my( $unready ) = grep { ! $_->get_ready() || $_->get_turn() != $self->get_turn() } values %$players;
$Data::Dumper::Maxdepth = 5;    print "Content-Type: text/html\n\n<pre>".Data::Dumper->Dump([$self,$unready]).'</pre>';
    return ! $unready;
} #everyone_ready

#
# Advance the new turn.
#
sub tick {
    my( $self ) = shift;

    #
    # parse, validate and collate commands. 
    # process rename commands and unload commnads, which do not depend on order
    #
    my( @load, @fire, @move, @build, @repair, @give );
    my $players = $self->get_players();
    for my $player (values %$players) {
        my $commands = $player->orders();
        for my $cmd_str (@$commands) {
            my( $cmd, @cmd ) = split(/\s+/,$cmd_str);
            if( uc($cmd) eq 'N' ) {
                #apply the command here, since the order is not critical
                rename_item( $player, @cmd );
            } #rename
            elsif( uc($cmd) eq 'U' ) {
                #apply the command here, since the order is not critical
                unload( $player, @cmd );
            } #unload
            elsif( uc($cmd) eq 'L' ) {
                push( @load, [$player,@cmd] );
            } #load
            elsif( uc($cmd) eq 'F' ) {
                push( @fire, [$player,@cmd] );
            } #fire
            elsif( uc($cmd) eq 'M' ) { #move
                push( @move, [$player,@cmd] );
            } #move
            elsif( uc($cmd) eq 'B' ) { #build
                my( $build_loc_id, $thing_to_build_id, @name ) = @cmd;
                my $name = join( ' ', @name );
                push( @build, [ $player->{ID}, $build_loc_id, $thing_to_build_id, $name ] );
            } #build
            elsif( uc($cmd) eq 'R' ) { #repair
                my( $ship_id, $repair_amount ) = @cmd;
                my $msg = { type    => 'command',
                            action  => 'repair',
                            command => $cmd_str,
                            result  => 'fail',    # change if success
                };
                if( $repair_amount > 0 ) {
                    my $ship = GServ::ObjProvider::fetch( $ship_id );
                    if( ref($ship) eq 'GServ::SE::Ship' && $ship->get_owner() eq $player ) {
                        push( @repair, [ $player, $ship, $repair_amount ] );
                    } else {
                        $msg->{err} = "not found";
                        $player->message( $msg );
                    }
                } else {
                    $msg->{err} = "No positive repair amount specified";
                    $player->message( $msg );
                }
            }
            elsif( uc($cmd) eq 'G' ) { #give
                my( $recip_id, $amount ) = @cmd;
                my $recipient = GServ::ObjProvider::fetch( $recip_id );
                my $msg = { type    => 'command',
                            action  => 'give',
                            command => $cmd_str,
                            result  => 'fail',    # change if success
                };
                if( $recipient && ref( $recipient ) eq 'GServ::SE::Player' ) {
                    if( $amount > 0 ) {
                        if( $recipient ne $player ) {
                            push( @give, [ $player, $recipient, $amount ] );
                        } else {
                            $msg->{err} = "Cannot give to yourself";
                            $player->message( $msg );
                        }
                    } else {
                        $msg->{err} = "No positive amount to give specified";
                        $player->message( $msg );
                    }
                } else {
                    $msg->{err} = "Recipient not found";
                    $player->message( $msg );
                }
            } #give	
        } #each command for player
    } #each player
    
    #### loads

    for my $load_order (@load) {
        load_carrier( @$load_order );
    }

    #### fire
    my( %damaged_by ); #target 2 list of attackers
    for my $fire (@fire) {
        my $target = fire( @$fire );
        push( @{$damaged_by{$target}}, $fire->[0] ); #add the player who fired
    }

    my( @dead_ships );
    for my $player (values %$players) {
        my $ships = $player->get_ships([]);
        for my $target (@$ships ) {
            if( $target->get_health() < 1 ) {
                my $loc = $target->get_location();

                # sets dead to 1 and kill everything (recursively) that is carried
                my @loaded = $target->kill(); 
                push( @dead_ships, $target,@loaded);
                for my $killed ($target,@loaded) {
                    message_observers( $loc, $player, {
                        target   => $killed,
                        action   => 'fire',
                        result   => 'destroyed',
                        actors   => $damaged_by{$target},
                        msg      => $killed->get_owner()->get_name()." ship ".$killed->namestr()." was destroyed",
                                       } );
                }
            } #dead
            else { #not quite dead. Heal up. Reset move
		$target->replenish();
            }
        } #each ship the player has
    } #each player's death check and heal

    # remove dead ships
    for my $dead (@dead_ships) {
        my $loc = $dead->get_location();
	my $owner = $dead->get_owner();
	$owner->remove_from_ships( $dead );
        $loc->remove_from_ships( $dead );
    }

    # move things and update maps
    for my $move (@move) {
        $self->move( @$move );
    } #move attempts

    #
    # determine ownership of systems, indict and bombardment.
    #
    my $systems = $self->get_sectors();
    for my $system (@$systems) {
        $system->set_indict( 0 ); #reset indict flag

        my $ships = $system->get_ships([]);
        my( %player2attack_power );

        for my $ship (@$ships) {
            if( $ship->get_prototype( 'attack_beams' ) ) {
                $player2attack_power{$ship->get_owner()->{ID}} += $ship->get_prototype( 'attack_beams' );
            }
        }

        # check if system is uncontested
        if( scalar( keys %player2attack_power ) == 1 ) {
            my( $attack_player_id ) = ( keys %player2attack_power );
            my $attacker = GServ::ObjProvider::fetch( $attack_player_id );
            next unless $player2attack_power{$attack_player_id};

            #
            # Can change hands if there is only one force in the system and there is no industry.
            #
            if( $system->get_owner() ne $attacker ) {
                if( $system->get_currprod() < 1 ) {
                    my $old_owner = $system->get_owner();
                    if( $old_owner ) {
                        message_observers( $system, $attacker, {
                            target   => $system,
                            action   => 'invasion',
                            result   => 'conquored',
                            actors   => [$attacker],
                            msg      => $attacker->get_name()." conquored ".$system->namestr(),
                                           } );                                           
                        $old_owner->remove_from_systems( $system );
                    }
                    $attacker->add_to_systems( $system );
                    message_observers( $system, $attacker, {
                        target   => $system,
                        action   => 'annex',
                        result   => 'annexed',
                        actors   => [$attacker],
                        msg      => $attacker->get_name()." annexed ".$system->namestr(),
                                       } );
                    $system->set_owner($attacker);
                } #conquoring
                else {
                    #bombardment
                    my $original = $system->get_currprod();
                    $system->set_currprod(  $system->get_currprod() - $player2attack_power{$attack_player_id} );
                    $system->set_indict( 1 );
                    if( $system->get_currprod() < 1 ) {
                        $system->set_currprod( 0 ); #minimum is zero
                    }
                    my $newprod = $system->get_currprod();
                    message_observers( $system, $attacker, {
                        target   => $system,
                        action   => 'bombardment',
                        result   => "reduced from $original to $newprod",
                        actors   => [$attacker],
                        msg      => $attacker->get_name()." bombarded ".$system->namestr()." bringing it to production $newprod from $original",
                                       } );
                } #bombardment
            } #if not owner
        } #uncontested power in system.

    } #each system
    
    #
    # builds
    #
    for my $build (@build) {
        my( $player_id, $b_location, $thing_id, $name ) = @$build;
        my $cmd_str = "B $b_location $thing_id $name";
        $cmd_str =~ s/\s*$//;
        my $player = GServ::ObjProvider::fetch( $player_id );
        my $prototype = $self->get_flavor()->get_prototypes()->{$thing_id};
        my $loc = GServ::ObjProvider::fetch( $b_location );
        my $msg = { type    => 'command',
                    action  => 'build',
                    command => $cmd_str,
                    result  => 'fail',    # change if success
                    err     => 'Internal Error on Build',
        };

        if( ref( $loc ) ne 'GServ::SE::Sector' ) {
            $msg->{err} = "Build location doesn't exist.";
        } elsif( !$prototype ) {
            $msg->{err} = "Unknown thing to build";
        } else {
            $msg->{location} = $loc;
            $msg->{target} = $prototype;
            if( $loc->get_owner() ne $player ) {
                $msg->{err} = "not owned by you.";
            }
            elsif( $loc->get_buildcap() >= $prototype->get_size() ) {
                if( $loc->get_owner() eq $player ) {
                    my $cost = $prototype->get_cost();
                    if( $prototype->get_tech_level() > $player->get_tech() ) {                        
                        $msg->{err} = "Tech level not high enough";
                    } else { #enough tech
                        if( $cost <= $player->get_rus() ) {
                            undef $msg->{err};
                            if( $prototype->get_type() eq 'SHIP' || $prototype->get_type() eq 'OIND' ) {
                                my $new_ship = new GServ::SE::Ship();
                                $new_ship->set_game( $self );

                                $new_ship->set_owner( $player );
                                $new_ship->set_prototype( $prototype );
                                $name ||= $prototype->get_name();
                                $new_ship->set_name( $name );

                                $loc->add_to_ships( $new_ship );
                                $new_ship->set_location( $loc );

                                $player->add_to_ships( $new_ship );
                                $player->set_rus( $player->get_rus() - $cost );

                                $msg->{result} = 'success';
                                $msg->{msg} = "Built ".$new_ship->namestr()." in location ".$loc->namestr()." for a cost of $cost";
                                
                                message_observers( $loc, $player, {
                                    target   => $prototype,
                                    action   => 'build',
                                    result   => "built",
                                    actors   => [$player],
                                    msg      => $player->get_name()." built ".$new_ship->namestr()." in location ".$loc->namestr(),
                                                   } );
                            }
                            elsif( $prototype->get_type() eq 'IND' ) {
                                if( $loc->get_currprod() < $loc->get_maxprod() ) {
                                    $loc->set_currprod($loc->get_currprod() + 1 );
                                    $msg->{result} = 'success';
                                    $msg->{msg} = "Built industry in location ".$loc->namestr()." for a cost of $cost";
                                    $player->set_rus( $player->get_rus() - $cost );

                                } else {
                                    $msg->{err} = "Already at max production";
                                }
                            }
                            elsif( $prototype->get_type() eq 'TECH' ) {
                                $player->set_tech( $prototype->get_tech_level() + 1 );
                                $player->set_rus( $player->get_rus() - $cost );
                                $msg->{result} = 'success';
                                $msg->{msg} = "Upgraded to tech ".$player->get_tech()." for a cost of $cost";
                            }
                            else {
                                $msg->{err} = "Unknown prototype type ".$prototype->get_type();
                            }
                            #
                            # calculate the maximum build size. It is 3 * the production + 
                            # number of orbital industries here.
                            #
                            $loc->set_buildcap( 3 * $loc->get_currprod() );
                            my $ships_here = $loc->get_ships([]);
                            for my $here_ship (@$ships_here) {
                                if( $here_ship->get_prototype('type') eq 'OIND' ) {
                                    $loc->set_buildcap( 1 + $loc->get_buildcap() );
                                }
                            }
                        } else {
                            $msg->{err} = "Not enough RUs";
                        }
                    } 
                }
            } else {
                $msg->{err} = "Location doesn't have enough production to build something of that size.";
            }
        }
	$player->message( $msg );
    } #each build

    #
    # repair
    #
    for my $rep (@repair) {
        my( $player, $ship, $amount ) = @$rep;
        my $cmd_str = "R $ship $amount";
        my $msg = { type    => 'command',
                    action  => 'repair',
                    command => $cmd_str,
                    result  => 'fail',    # change if success
                    err     => 'Internal Error on Repair',
        };
        if( ! $ship->get_dead() ) {
            if( $player->get_rus() < int(.6 + $amount / 2 ) ) {
                $amount = 2 * $player->get_rus();
            } 
            if( $amount > 0 ) {
                my $start_health = $ship->get_health();
                my $max_heal = $ship->get_prototype('defense') - $ship->get_health();
                if( $amount > $max_heal ) {
                    $amount = $max_heal;
                }
		if( $amount > 0 ) {
		    my $cost = int(.6+$amount/2);
		    $player->set_rus( $player->get_rus() - $cost );
		    $ship->set_health( $ship->get_health() + $amount );
		    my $loc = $ship->get_location();
		    $msg->{result} = 'success';
		    $msg->{msg} = "Repaired ship ".$ship->namestr()." from $start_health to ".$ship->get_health()." for a cost of $cost at ".$loc->namestr();
		}
            } else {
                $msg->{err} = "Out of RUs";
            }
        } else {
            $msg->{err} = "Ship was destroyed";
        }
        $player->message( $msg );
    } #each repair order

    #
    # Give
    #
    for my $give (@give) {
        my( $player, $recipient, $amount ) = @$give;
        my $cmd_str = "G $recipient->{ID} $amount";
        my $avail = $player->get_rus();
        my $msg =  {
            type    => 'command',
            action  => 'give',
            command => $cmd_str,
            target  => $recipient,
            actor   => $player,
            result  => 'success',
        };
        if( $avail < $amount ) {
            $amount = $avail;
        }
        if( $amount > 0 ) {
            $recipient->set_rus( $recipient->get_rus() + $amount );
            $player->set_rus( $player->get_rus() - $amount );
            $msg->{msg} = "Gave $amount to ".$recipient->namestr();
        } else {
            $msg->{result} = 'fail';
            $msg->{err} = "Out of RUs";
        }
        $player->message( $msg );
    }

    #
    # Calculate production RUs and maps
    #
    for my $player (values %$players) {
        my $player_systems = $player->get_systems( [] );
        my $rus = $player->get_rus();
        for my $system (@$player_systems) {
            if( $system->get_indict() == 0  ) {
                $rus += $system->get_currprod();
            }
        }
        $player->set_rus( $rus );
	$player->set_orders([]);
	$player->set_ready(0);
	$player->set_turn( $self->get_turn() + 1 );
    } #each player
    $self->set_turn ( $self->get_turn() + 1 );
    $self->make_player_maps();
} #tick

#
# Called for each turn.
#
sub make_player_maps {
    my $self = shift;

    my $players = shift || $self->get_players();
    for my $player (values %$players) {
        # map 
        my $g = new GraphViz( directed => 0, ratio => 8.0/7 );
        my $map = $player->get_maps({});
        my( %mapped_edges );
        for my $mnode (values %$map) {
            my $loc = $mnode->get_system();
            my $owner = $loc->get_owner();

            my $label = $loc->get_name();
            $g->add_node( $loc->{ID},
                          label  => $label,
                          style  => $loc->get_owner() eq $player ? 'solid' : 'filled', 
                          shape  => 'box',
                          width  => 0.3,
                          height => 0.3,
                          fontsize => 10,
                          URL => $loc->{ID},
                          color => $loc->get_owner() eq $player ? 'Turquoise' :
                          $loc->get_owner() ? 'pink' : 'Coral',
                );
            my $connections = $loc->get_links();
            for my $con (values %$connections) {
                # check if this node leads to an other mapped node, or to an unknown connection.
                if( $map->{$con->{ID}} ) {
                    #known
                    $g->add_edge( $con->{ID}, $loc->{ID} ) 
                        unless $mapped_edges{"$con->{ID} $loc->{ID}"} || $mapped_edges{"$loc->{ID} $con->{ID}"};
                    $mapped_edges{"$con->{ID} $loc->{ID}"} = 1;
                } else {
                    #add unexplored node
                    $g->add_node( $con->{ID},
                                  label  => $con->get_name( ),
                                  style  => 'filled', 
                                  shape  => 'box',
                                  width  => 0.3,
                                  height => 0.3,
                                  fontsize => 10,
                                  URL => $con->{ID},
                                  color => 'Chartreuse',
                        );
                    $g->add_edge( $con->{ID}, $loc->{ID} ) 
                }
            } #each connection from node
        } #each node in players map
        my $turn = $self->get_turn();

        my $base = Cwd::getcwd();
        my $dir = "/home1/irrespon/proj/data/StellarExpanse/maps/$self->{ID}/$turn";

        mkdir $dir unless -e $dir;
        open(FH, ">$dir/".$player->{ID}.".png");
        print FH $g->as_png;
        close(FH);
        open(FH, ">$dir/".$player->{ID}.".cmapx");
        my $cpam = $g->as_cmapx;
        print FH $cpam;
        close(FH);    

        # 3.png: PNG image, 795 x 504, 8-bit/color RGBA, non-interlaced
        my $x = `file $dir/$player->{ID}.png`;
        my( $w, $h );
        if( $x =~ /^[^,]*,\s*(\d+)\s*[Xx]\s*(\d+)/ ) {
            ( $w, $h ) = ( $1, $2 );
        }

        my $jsfile = "$dir/$player->{ID}.js";
        open(FH, ">$jsfile");
        print FH "function set_dimentions() {\n";
        print FH "img_w = $w;\nimg_h = $h;\n}\n";
#<area shape="rect" href="#se79" title="pasionfruit(79)\nprod 5/5" alt="" coords="557,379,672,424"/>
        print FH "function init_map(c) {\n";
        while( $cpam =~ /(.*?)href=\"([^\"]*)\"(.*?)coords=\"([^\"]*)\"(.*)/is ) {
            my( $name, $coords ) = ( $2, $4 );
            $cpam = $5;
            my( $x1, $y1, $x2, $y2 ) = split( /,/, $coords );
            my $w = $x2 - $x1;
            my $h = $y2 - $y1;
            print FH "c.add_control( make_click( c, function() { show_system($name) }, $x1, $y1, $w, $h ) );\n";
        }
        print FH "}\n";
        close( FH );

    } #each player
} #make_player_maps

####---#######-----------------####-------#
###-------------- Commands ------------###
#-----######------------------####----###

#
# Unloads a ship from a carrier. Turn is in the form 'U <shipid to unload>'
#
sub unload {
    my( $player, @cmd ) = @_;
    my $cmd_str = join(' ','U',@cmd);
    my( $loaded_id ) = @cmd;
    my $obj = GServ::ObjProvider::fetch( $loaded_id );

    my $msg = {
        type    => 'command',
        action  => 'unload',
        command => $cmd_str,
        target  => $obj,
        result  => 'fail',
    };

    if( $obj && $obj->get_owner() eq $player ) {
        if( ref($obj) eq 'GServ::SE::Ship' ) {
            my $loaded_in = $obj->get_location();
            if( $loaded_in ) {
                if( ref( $loaded_in ) eq 'GServ::SE::Ship' ) {
                    # validated case
                    my $new_loc = $loaded_in->get_location();
                    $new_loc->add_to_ships( $obj );
                    $loaded_in->remove_from_carried( $obj );
                    $loaded_in->set_free_rack( $loaded_in->get_free_rack() + $obj->get_prototype('size') );
                    $obj->set_location( $new_loc );
                    $msg->{location} = $new_loc;
                    $msg->{result} = 'success';
                    $msg->{msg} = "Unloaded ".$obj->namestr()." from carrier ".$loaded_in->namestr()." in system ".$new_loc->namestr();
                    message_observers( $new_loc, $player, {
                        target   => $obj,
                        actors   => [$loaded_in],
                        action   => 'unload',
                        result   => 'unloaded',
                        msg      => $player->get_name()." : ".$loaded_in->namestr()." unloaded ".$obj->namestr(),
                                       } );
                } else {
                    $msg->{err} = "not in a ship";
                }
            } else {
                $msg->{err} = "SERVER ERROR : not in any location";
            }
        } else {
            $msg->{err} = "You can only unload ships";
        }
    }
    else {
        $msg->{err} = "not found";
    }
    $player->message( $msg );
    return undef;
} #unload

#
# Loads a ship onto a carrier. Command is in the format 'L <ship id to load> <carrier id>'
#
sub load_carrier {
    my( $player, @cmd ) = @_;
    my $cmd_str = join(' ','L',@cmd);
    my( $ship_id, $carrier_id ) = @cmd;
    my $ship = GServ::ObjProvider::fetch( $ship_id );
    my $carrier = GServ::ObjProvider::fetch( $carrier_id );

    my $msg = {
        type    => 'command',
        action  => 'load',
        command => $cmd_str,
        target  => $ship,
        actor   => $carrier,
        result  => 'fail',
    };

    if( ref($ship) eq 'GServ::SE::Ship' 
        && ref($carrier) eq 'GServ::SE::Ship' 
        && $ship->get_owner() eq $player 
        && $carrier->get_owner() eq $player ) 
    {
        my $ship_loc = $ship->get_location();
        $msg->{location} = $ship_loc;
        my $carrier_loc = $carrier->get_location();
        if( $ship_loc && $carrier_loc ) {
            if( $ship_loc eq $carrier_loc ) {
                my $free = $carrier->get_free_rack();
                if( $free >= $ship->get_prototype('size') ) {
                    ######  Success
                    $carrier_loc->remove_from_ships( $ship );
                    $ship->set_location( $carrier );
                    $carrier->add_to_carried( $ship );
                    $carrier->set_free_rack( $free - $ship->get_prototype( 'size' ) );
                    $msg->{result} = 'success';
                    $msg->{msg} = "loaded ".$ship->namestr()." on to carrier ".$carrier->namestr( )." in sector ".$ship_loc->namestr( );
                    message_observers( $ship_loc, $player, {
                        target   => $ship,
                        action   => 'load',
                        result   => 'loaded',
                        actors   => [$carrier],
                        msg      => $player->get_name()." : ".$carrier->namestr()." loaded ".$ship->namestr(),
                                       } );
                } else {
                    $msg->{err} = "not have enough room";
                }
            } else {
                $msg->{err} = "not in same place";
            }			
        } else {
            $msg->{err} = "SERVER ERROR : not in a location";
        }
    } else {
        $msg->{err} = "not found";
    }

    $player->message( $msg );
    return undef;
} #load_carrier

sub fire {
    my( $player, @cmd ) = @_;
    my $cmd_str = join(' ','F',@cmd);
    my( $fire_ship_id, $strength, $target_id ) = @cmd;
    my $ship = GServ::ObjProvider::fetch( $fire_ship_id );
    my $target = GServ::ObjProvider::fetch( $target_id );

    my $msg = {
        type    => 'command',
        action  => 'fire',
        command => $cmd_str,
        target  => $target,
        actor   => $ship,
        result  => 'fail',
    };

    if( ref($ship) eq 'GServ::SE::Ship'&& ref($target) eq 'GServ::SE::Ship' ) {
        if( $ship->get_owner() eq $player ) {
            if( $target->get_owner() ne $player ) {
                my( $ship_loc, $target_loc ) = ( $ship->get_location(), $target->get_location() );
                if( ref($ship_loc) eq 'GServ::SE::Sector' && ref($target_loc) eq 'GServ::SE::Sector'  ) {
                    if( $ship_loc eq $target_loc ) {
                        my $targets_left = $ship->get_remaining_targets();
                        if( $targets_left > 0 ) {
                            $ship->set_remaining_targets( $targets_left - 1 );
                            my $beams_left = $ship->get_remaining_beams();
                            if( $beams_left > $strength ) {
                                $strength = $beams_left;
                                $msg->{warn} = "Strength cannot exceed beams available. Strength set to $strength";
                            }
                            $target->set_health( $target->get_health() - $strength );
                            $msg->{result} = 'success';
                            my $msgstr;
                            if( $ship->get_prototype('self_destruct') ) {
                                $ship->kill();
                                $msgstr = $ship->namestr( )." blew up on ".$target->get_owner()->get_name()." ".$target->namestr( )." with $strength damage";
                            } else {
                                $msgstr = $ship->namestr( )." fired on ".$target->get_owner()->get_name()." ".$target->namestr( )." with $strength beams";
                            }
                            $msg->{msg} = $msgstr;
                            message_observers( $ship_loc, $player, {
                                target   => $target,
                                action   => 'fire',
                                result   => 'attacked',
                                msg      => $player->get_name()." $msgstr",
                                               } );
                            $player->message( $msg );
                            return $target;
                        } else {
                            $msg->{err} = "out of targets";
                        }
                    } else {
                        $msg->{err} = "Not in same location";
                    }
                } else {
                    $msg->{err} = "SERVER ERROR : not in location";
                }
            } else {
                $msg->{err} = "You may not fire on your own ship";
            }
        } else {
            $msg->{err} = "not found";
        }
    } else {
        $msg->{err} = "not found";
    }
    $player->message( $msg );
    return undef;
} #fire

sub move {
    my( $self, $player, @cmd ) = @_;
    my $cmd_str = join(' ','M',@cmd);
    my( $ship_id, $location_id ) = @cmd;
    my $ship = GServ::ObjProvider::fetch( $ship_id );
    my $location = GServ::ObjProvider::fetch( $location_id );
    my $msg = {
        type        => 'command',
        action      => 'move',
        command     => $cmd_str,
        actor       => $ship,
        destination => $location,
        result      => 'fail',
    };

    if( $location ) {
        if( ref($ship) eq 'GServ::SE::Ship' 
            && $ship->get_owner() eq $player )
        {
            if( ! $ship->get_dead( ) ) {
		my $cur_loc = $ship->get_location();
		$msg->{origin} = $cur_loc;
                if( $ship->get_remaining_move() > 0 ) {


                    my $connections = $cur_loc->get_links();
                    if( $connections->{$location->{ID}} ) {
                        # success, set the location of the ship, and update its move
                        $ship->set_location( $location );
                        $location->add_to_ships( $ship );

                        $cur_loc->remove_from_ships( $ship );
                        my $maps = $player->get_maps();
                        if( $maps->{$location->{ID}} || $ship->get_prototype('name') eq 'Scout' ) {
                            $ship->set_remaining_move( $ship->get_remaining_move() - 1 );
                        } else {
                            $ship->set_remaining_move( 0 );
                        }

                        #update the player maps to include this location
                        my $node = $maps->{$location->{ID}};

                        # check if this system is on the players starchart. if not, make an entry
                        if( ! $node ) {
                            $node = new GServ::Obj();
                            $node->set_game( $self );
                            $node->set_system( $location );
                            $maps->{$location->{ID}} = $node;
                            $node->add_to_notes( "Discovered on turn ".$self->get_turn() );
                        }

                        # update the starchart entry to include production values and ships present
                        $node->set_seen_production( $location->get_currprod() );
                        $node->set_seen_owner( $location->get_owner() );
                        my $ships = $location->get_ships( [] );
                        my( @my_ships, @their_ships );
                        for my $oship (@$ships) {
                            if( $oship->get_owner() eq $player ) {
                                push( @my_ships, $oship ) ;
                            } else {
                                push( @their_ships, $oship ) ;
                            }
                        }                    
                        $node->set_their_ships( \@their_ships );
                        $node->set_my_ships( \@my_ships );

                        # command message and going to/coming from messages
                        $msg->{result} = 'success';
                        $msg->{msg} = $ship->namestr()." moved from ".$cur_loc->namestr()." to ".$location->namestr();
                        $msg->{location} = $location;
                    } else {
                        $msg->{err} = "cannot reach";
                    }       
                } else {
                    $msg->{err} = "not enough move";
                }         
            } #not quite dead
            else {
                $msg->{err} = "ship destroyed";
            }
        } else {
            $msg->{err} = "ship not found";
        }
    } else {
        $msg->{err} = "destination doesn't exist";
    }
    $player->message( $msg );

    return undef;
} #move

####---#######-----------------####-------#
###-------------- Utilities -----------###
#-----######------------------####----###


#
# Sends anyone who can see an event a message for a location.
#
sub message_observers {
    my( $loc, $observed, $message ) = @_;
    $message->{type} ||= 'info';
    $message->{location} ||= $loc;

    my %seen;
    my $loc_owner = $loc->get_owner();
    my @ship_owners = map { $_->get_owner() } @{$loc->get_ships( [] )};

    for my $o (@ship_owners,$loc_owner) {
        next unless $o;
        next if $observed->{ID} == $o->{ID} && $message->{action} =~ /^(load|unload|build|fire)$/;
        next if $seen{$o};
        $o->message( $message );
        $seen{$o} = 1;
    }
    return undef;
}  #message_observers




####---#######-----------------####-------#
###---------------- Setup -------------###
#-----######------------------####----###

sub join {
    my( $self, $acct ) = @_;
    my $avail_players = $self->get_available_players();
    my $player = shift @$avail_players;
    if( $player ) {
	$player->set_name( $acct->get_name() );
	my $players = $self->get_players();
	$players->{$acct->{ID}} = $player;
    } 
    return $player;

} #join

sub player {
    my( $self, $acct ) = @_;
    my $players = $self->get_players();
    return $players->{$acct->{ID}};
}

sub can_activate {
    my $self = shift;
    my $avail_players = $self->get_available_players();
    return @$avail_players == 0;
}

sub leave {
    my( $self, $acct ) = @_;
    my $players = $self->get_players();
    my $player = $players->{$acct->{ID}};
    delete $players->{$acct->{ID}};
    if( $player ) {
	$self->add_to_available_players( $player );
    }
} #leave

#
# Called upon creation of game.
#
sub init_game {
    my $self = shift;
    $self->set_turn(0);
    # set up players. Once these all have been claimed by accounts, the game can begin.
    $self->set_players({});
    my $players = $self->get_available_players([]);
    for (1..$self->get_number_players() ) {
	my $player = new GServ::SE::Player();
	$player->set_game( $self );
	push( @$players, $player );
    }

    my $flav = $self->get_flavor();
    unless( $flav ) {
        die "Flavor not set";
    }

    my $path = "/home1/irrespon/proj/data/StellarExpanse";
    my $config_path = File::Spec->catfile($path, '/', 'game.config');
    my $configuration = new Config::General(
        -ConfigFile => $config_path,
        -ConfigPath => [File::Spec->catdir($path, '/'), $path],
        -LowerCaseNames => 1,
        -IncludeAgain => 1,
        -MergeDuplicateBlocks => 1,
        );
    my %configuration = $configuration->getall;
#    my $group_factory = new Univ::Model::Generator::GroupFactory;
    my $targetsect = $configuration{target_sector_count};
    die "Need target sector count" if (!defined($targetsect));

    #random names for fun
#    my( @snames ) = `cat /etc/dictionaries-common/words | egrep -v '/[^a-zA-Z_ ].*[^a-zA-Z_ ]/' | sort -R | head -$targetsect`;
#    my( @snames ) = `cat /usr/share/dict/american-english | egrep -v '/[^a-zA-Z_ ].*[^a-zA-Z_ ]/' |sort -R | head -$targetsect`;
    my $snames = UTIL::RandWords::get_random_words( $targetsect );
    $self->{rand_names} = [map { s/\s*$//s; $_ } map { s/[^a-zA-Z_ ]/_/gs; $_ } map { s/\s*$//s; $_ } @$snames];

    for my $p (@$players ) {
        $p->set_rus( $self->get_starting_resources() );
        $p->set_tech( $self->get_starting_tech_level() );
    } #each player
    
    
    my @links;

    my $unclaimed_groups = [];
    my $empire_groups = [];
    my $sector_count = 0;
    for my $p (@$players ) {
        my $map = $p->get_maps( {} );
        my $g = $self->make_random_group( \%configuration, "empires", $p);
        my $gsecs = $g->{sectors};
        for my $gsec (@$gsecs) {
            next unless $gsec->get_owner();
            my $node = new GServ::Obj();
            $node->set_game( $self );
            $node->set_system( $gsec );
            $map->{ $gsec->{ID} } = $node;
            $node->add_to_notes( "Starting Sector" );
        }
        $g->{is_empire} = 1;
        $sector_count += $g->get_sector_count();
        push @$empire_groups, $g;
    }
    
    my $base_group_name = $configuration{basegroups} ? 'basegroups' : 'groups';
    my $g = $self->make_random_group( \%configuration, $base_group_name);
    $sector_count += $g->get_sector_count();
    push @$unclaimed_groups, $g;


    while ($sector_count < $targetsect) {
        my $g = $self->make_random_group(\%configuration, "groups");
        $sector_count += $g->get_sector_count();
        push @$unclaimed_groups, $g;
    }
    

    #
    # Pick a starting group, then glom other groups into it until all the groups are connected.
    #
    my( @selector );
    for my $g (@$unclaimed_groups) {
        for(1..$g->get_outbound_count()) {
            push @selector, $g;
        }
    }
    my $start_group = $selector[int(rand(scalar @selector))];

    my $glom = new GServ::SE::GlomGroup();
    $glom->glom( $start_group );

    for my $g (@$unclaimed_groups) {
        next if $g eq $start_group;
        $glom->glom( $g );	
    }

    my( @free_groups ) = grep { $_->get_outbound_count() > 0 } (@$empire_groups);
    my $tries = 0;
    my $unconnected_empire_sectors = 0;
    for my $fg (@free_groups) {
        $unconnected_empire_sectors += $fg->get_outbound_count();
    }
    while( @free_groups && $unconnected_empire_sectors > 1 && $tries < 10 ) {
        for my $g (@free_groups) {
            $glom->connect( $g ) if $g->get_outbound_count() > 0;
        }
        ( @free_groups ) = grep { $_->get_outbound_count() > 0 } (@free_groups);
        ++$tries;
        $unconnected_empire_sectors = 0;
        for my $fg (@free_groups) {
            $unconnected_empire_sectors += $fg->get_outbound_count();
        }
    }
    die "Unable to make connections" if $tries == 10;

    my( @free_groups ) = grep { $_->get_outbound_count() > 0 } (@$unclaimed_groups);
    while( $glom->get_unlinked_groups() > 1 && @free_groups > 1) {
        for my $g (@free_groups) {
            $glom->connect( $g ) if $g->get_outbound_count() > 0;
        }
        ( @free_groups ) = grep { $_->get_outbound_count() > 0 } (@free_groups);
    }

# -------- make map ------------------------------------
    my $gv = new GraphViz(directed => 0);    
    my %seen;
    for my $g (@$empire_groups,@$unclaimed_groups) {
        my $sects = $g->{sectors};
        for my $s (@$sects) {
            $gv->add_node( $s->{ID}, 
                           label => $s->get_name( $s->{ID} ),
                );
            my $links = $s->get_links();
            for my $link_to (keys %$links) {
                unless( $seen{$link_to}{$s->{ID}} ) {
                    $gv->add_edge( $s->{ID} => $link_to );
                    $seen{$s->{ID}}{$link_to} = 1;
                }
            } #each link
        } #each sector
    } #each group

    my $dir = "/home1/irrespon/proj/data/StellarExpanse/maps/$self->{ID}";
    mkdir $dir unless -e $dir;
    open(FH, ">$dir/map.png");
    print FH $gv->as_png;
    close(FH);
#---

    $self->make_player_maps( { map { $_->{ID} => $_  } @$players } );

} #init_game


sub make_random_group {
    my ( $self, $full_config, $basename, $owner) = @_;

    #
    # Looks up the configuration data structure for the basename.
    # Picks a random item in the configuration to use as a starting
    #  group where group is a nodal configuration of systems.
    #

    die "No $basename in configuration" if (!exists($full_config->{$basename}));
    my $part_config = $full_config->{$basename}->{group};

    my @keys = keys %$part_config;
    die "No groups in $basename configuration" if (scalar @keys == 0);
    my $choice = int(rand(scalar @keys));
    my $group_config = $part_config->{$keys[$choice]};


    # Now do more interesting stuff, sectors and internal link conversion
    my $sectors = $group_config->{'sector'};
    my @needProd;
    my @needMaxProd;

    my( %key2GSector );

    my $word = shift @{$self->{rand_names}};
    chomp $word;
    $word =~ s/[\'\"]//g;

    for my $key (sort keys %$sectors) {
        my $sector_template = $sectors->{$key};

        my $newsector = new GServ::SE::Sector();
        $newsector->set_game( $self );
        $self->add_to_sectors( $newsector );
        $key2GSector{$key} = $newsector;

        my $moniker = $key eq 'A' ? 'alpha' :
            $key eq 'B' ? 'beta' :
            $key eq 'C' ? 'gamma' :
            $key eq 'D' ? 'rho' : 
            $key eq 'E' ? 'epsilon' : 
            $key eq 'F' ? 'zeta' : 
            $key;
        $newsector->set_name( "$moniker $word" );

        
        my $prod_type = $sector_template->{prod_type} || 'default';

        # ---- set max and current production values ----
        my $rangeString = getProdValue($full_config, $sector_template, $prod_type, 'sectormaxprodrange');
        my ($min, $max) = split ' ',$rangeString;
        $min = $min || 0;   $max = $max || 0;
        
        my $maxprod = $max < $min ? $min : int(rand($max-$min+1) + $min);
        $newsector->set_maxprod( $max < $min ? $min : int(rand($max-$min+1) + $min) );

        my $rangeString = getProdValue($full_config, $sector_template, $prod_type, 'sectorprodrange');

        my ($min, $max) = split ' ',$rangeString;
        $min = $min || 0;   $max = $max || 0;
        my $curprod = $max < $min ? $min : int(rand($max-$min+1) + $min);

        if ($curprod > $maxprod) {
            $curprod = $maxprod;
        }	
        if( $owner && $sectors->{$key}{owner} != -1 ) {
            $newsector->set_owner( $owner );
            $owner->add_to_systems( $newsector );
            $maxprod = $sector_template->{maxprod};
            $curprod = $sector_template->{currprod};	    
        }
        $newsector->set_currprod( $curprod );
        $newsector->set_maxprod( $maxprod );
        $newsector->set_buildcap( 3 * $curprod );
        $key2GSector{$key}->set_outbound_links( $sectors->{$key}->{outbound_links} );	

    } #each sector group key

    #
    # Map out the sector to sector links that are internal to this group.
    #
    my $internal_links = $group_config->{internal_link};
    $internal_links = [ $internal_links ] unless ref( $internal_links );
    for my $link (@$internal_links) {
        $link =~ s/^\s*//; $link =~ s/\s*$//;
        my( $sectA, $sectB ) = map { $key2GSector{$_} } split ' ', $link, 2;
        die "Bad configuration, $link" unless $sectA && $sectB;
        $sectA->link_sectors( $sectB );
    } #each internal to group link

    my $group = new GServ::SE::Group();
    $group->set_sectors( [values %key2GSector] );
    return $group;
} #make_random_group

#
# Builds a list of values that the group has for the given key.
# The values have a weight, and the values appear as many times
# in the list as the value of their weight.
#
sub buildRangeStringOptList {
    my ($group, $key) = @_;
    my $rangeStringOpts;
    my $subgroup = $group->{prod_type};
    
    foreach my $ptg (values %{$subgroup}) {
        my $s = $ptg->{$key} || 0;
        my $c = $ptg->{weight} || 1;
        for (my $i = 0; $i < $c; ++$i) {
            push @$rangeStringOpts, $s;
        }
    }   
    return $rangeStringOpts;
} #buildRangeStringOptList

#
# Gets the production value for a production type
#
sub getProdValue {
    my( $full_config, $sector_template, $prod_type, $prod_key ) = @_;
    # create a list of value options, like [0,1,1,1,5,5,5,8,9] and randomly pick from that list. The 
    # list is weighted, and the weightings show up as repetition of a value in the list.
    my $rangeStringOpts = $sector_template->{$prod_key} || 
        buildRangeStringOptList($sector_template->{prod_type_group}{$prod_type}, $prod_key) ||
        buildRangeStringOptList($full_config->{prod_type_group}{$prod_type}, $prod_key) ||
        ["0"];
    my $opt = 0;
    if( scalar( @$rangeStringOpts ) ) {
        $opt = $rangeStringOpts->[int(rand(scalar @{$rangeStringOpts}))];
    }
    return $opt;
} #getProdValue

#
# Verifies that the game map is sane.
#
sub verify_map {
    my $self = shift;
    my $sectors = $self->get_sectors();
    return 0 unless $sectors && @$sectors;
    return $sectors->[0]->valid_links({});
} #verify_map

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut
