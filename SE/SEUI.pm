package G::ARCADE::StellarExpanse::SEUI;

use strict;

use base 'UTIL::UI';

#
# 
#
sub edit_game {
    my( $self, $acct, $form, $game ) = @_;

    G::Base::do_query("BEGIN");
    $self->check_updates( $form );
    my( $gamename ) = ( ref( $game ) =~ /([^:]+)$/ );
    
    $self->print_html_open( "Editing game $gamename", $acct );
    print "<HR>";

    if( $game->get_game_state() eq  $G::Game::IN_PROGRESS ) {
	$self->alt_table( 
	    [ 'Name', $game->get_name() ],
	    [ 'ID', $game->{ID} ],
	    [ 'Number of Players', $game->get_number_players() ],
	    [ 'Starting Player Resources',$game->get_starting_resources() ],
	    [ 'Starting Player Tech Level', $game->get_starting_tech_level() ],
	    [ 'Starting Number of Sectors', $game->get_starting_sectors() ],
	    [ 'Turn', $game->get_turn() ],
#        [ 'Turns are run',$self->upsel( $game, 'turns_run', ['every night','after all players are ready'], ['every_night','when_ready'] ) ],
	    );
	    print '<P>'.$self->href( "javascript:void(0)", 'back one turn', qq~onclick='if(confirm("Go back a turn?")){ window.location="?session=$form->{session}&rollback=1&editing_game=$game->{ID}"}'~ );
    } else {

	$self->alt_table( 
	    ['Name',$self->upfield( $game, 'name' )],
	    [ 'ID', $game->{ID} ],
	    [ 'Number of Players',$self->upfield( $game, 'number_players' ) ],
	    [ 'Starting Player Resources',$self->upfield( $game, 'starting_resources' ) ],
	    [ 'Starting Player Tech Level', $self->upfield( $game, 'starting_tech_level' ) ],
	    [ 'Starting Number of Sectors', $self->upfield( $game, 'starting_sectors' ) ],
#        [ 'Turns are run',$self->upsel( $game, 'turns_run', ['every night','after all players are ready'], ['every_night','when_ready'] ) ],
	    );
    }	

    print qq~<input type=hidden name="session" value="$form->{session}">~;
    print qq~<input type=hidden name="editing_game" value="$form->{editing_game}">~;
    print "<P><input type=submit value=Update>";
    
    if( ! $game->get_players({})->{$acct->{ID}} ) {
	print '<P>'.$self->href("?session=$form->{session}&join_game=$game->{ID}","join");	    
    }


    print '<P>'.$self->href( "?session=$form->{session}", 'back to lobby' );
    print '<P>'.$self->href( "javascript:void(0)", 'delete', qq~onclick='if(confirm("Really Delete?")){ window.location="?session=$form->{session}&delete_game=$game->{ID}"}'~ );
    $self->print_html_close();

} #edit_game

sub play_game {
    my( $self, $player, $form, $msg ) = @_;
#    $G::Base::NO_SAVE = 1;

    my $sess = $player->get_account()->get_session();

    my $game = $player->get_game();

    my $status = $game->get_game_state();
    
    if( $status eq $G::Game::IN_PROGRESS ) {
###############################################
########        ###########################
#######  GAPHER  #####################
#######          ###############
#######################

	####################
	#         read inputs


	# orders are stored in url parameters 
	#          idx is the number of the order
	#   Build : ORD_BSS_systemid_idx - id of what to build
	#           ORD_BSN_systemid_idx - name of thing to build
	#    Move : ORD_SM_shipid_ids - space, comma or semicolon separated list of
	#                           systemids to move to
	#    Move : ORD_PM_shipid - path move. specifies an endpoint destination.
	#    Fire : ORD_ST_shipid_idx - id of who to shoot
	#         : ORD_SS_shipid_idx - amount of how much to shoot
	#  Rename : ORD_REN_objectid -  new name 
	#  Repair : ORD_RE_shipid - amount of damage to repait
	#    Load : ORD_LO_shipid - ship ids (\0 separated) to load
	#  Unload : ORD_UL_shipid - unloads ship that has id
	#
	#  additional free form orders : ORD_ADDITIONAL
	#
	my( @ords, %cmds );
	my( %renames, %carrier, %uncarrier );
	if( $form->{HORD} ) {
	    my( @ord_keys ) = grep { /^ORD_/ } keys %$form;

	    if( $form->{set_not_ready} ) {
		$player->set_ready( 0 );
	    }

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
		    push( @{$cmds{$sid}}, "M $sid $sys" );
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
			    push( @ords, "B $buildwhat $system $thisbm" );
			    push( @{$cmds{$system}}, "B $buildwhat $system $thisbm" );
			}
		    }
		} elsif( $orda =~ /^ORD_PM_(\d+)/ ) { #path move
		    my $ship = G::Base::fetch( $1 );
		    my $loc = $ship->get_location();
		    my $dest = G::Base::fetch( $form->{$orda} );
		    my $path = $ship->get_remaining_move() ? shortest( $loc, $dest, $ship->get_remaining_move() ) : [];
		    for my $p (@$path) {
			push( @ords, "M $ship->{ID} $p->{ID}" );
		    }
		} elsif( $orda =~ /^ORD_ST_(\d+)_(\d+)/ ) { #fire
		    my( $shipid, $idx ) = ( $1, $2 );
		    push( @ords, "F $shipid ".$form->{"ORD_SS_${shipid}_$idx"}." ".$form->{$orda} ) if $form->{"ORD_SS_${shipid}_$idx"} > 0;
		    push( @{$cmds{$shipid}}, "F $shipid ".$form->{"ORD_SS_${shipid}_$idx"}." ".$form->{$orda} ) if $form->{"ORD_SS_${shipid}_$idx"} > 0;
		} elsif( $orda =~ /^ORD_REN_(\d+)/ ) { #rename
		    my $id = $1;
		    if( $form->{"HORD_REN_$id"} ne $form->{$orda} ) {
			push( @ords, "N $id $form->{$orda}" );
			push( @{$cmds{$id}}, "N $id $form->{$orda}" );
			$renames{$id} = $form->{$orda};
		    }
		} elsif( $orda =~ /^ORD_RE_(\d+)/) { #repair
		    my $cid = $1;
		    $form->{$orda} =~ s/[\"\']/_/gs;
		    push( @ords, "R $cid $form->{$orda}" ) if $form->{$orda} > 0;
		    push( @{$cmds{$cid}}, "R $cid $form->{$orda}" ) if $form->{$orda} > 0;
		} elsif( $orda =~ /^ORD_LO_(\d+)/) { #load
		    my $id = $1;
		    $carrier{$id} = $form->{$orda};
		    my( @ids ) = split( /\0/, $form->{$orda} );
		    push( @ords, map { "L $_ $id" } @ids );
		    push( @{$cmds{$id}}, map { "L $_ $id" } @ids );
		} elsif( $orda =~ /^ORD_UL_(\d+)/ ) { #unload
		    my $id = $1;
		    $uncarrier{$id} = 1;
		    push( @ords, "U $id" );	    
		    push( @{$cmds{$id}}, "U $id" );	    
		}
	    } #each order
	    push( @ords, split(/[\n\r]+/s,$form->{ORD_ADDITIONAL} ) ) if $form->{ORD_ADDITIONAL};

	    
	    # Check existing orders
	    my $reset = 0;

	    if( $form->{turn} == $game->get_turn() ) {
		if( @ords ) {
		    $player->set_next_state( 'orders', [@ords] );
		}
		if( $form->{set_ready} && $form->{turn} == $game->get_turn() ) {
		    $player->set_ready( 1 );
		}
	    } else {
		$reset = 1;
	    }

	    if( $reset ) {
		@ords = ();
		%cmds = ();
		%renames = ();
		%carrier = ();
		%uncarrier = ();
		my( @ord_keys ) = grep { /^ORD_/ } keys %$form;
		for my $ok (@ord_keys ) {
		    delete $form->{$ok};
		}
	    }
	} else {
	    my $ords = $player->get_next_state( 'orders' );
	    my( %bthing_name2idx );
	    my $build_idx = 0;
	    my %s2fire_idx;
	    my %s2move_idx;
	    for my $o (@$ords) {
		push( @ords, $o );
		if( $o =~ /^B (\d+) (\d+)( (.*)( (\d+)))?/) {
		    my( $what, $sys, $name, $nameidx ) = ( $1, $2, $4, $6 );
		    my $index = $build_idx;
		    if( defined $bthing_name2idx{"${what}_$name"} ) {
			$index = $bthing_name2idx{"${what}_$name"};
		    } else {
			$bthing_name2idx{"${what}_$name"} = $index;
			$build_idx++;
		    }
		    $form->{"ORD_BSS_${sys}_$index"} = $what;
		    $form->{"ORD_BSN_${sys}_$index"} = $name;
		    $form->{"ORD_BSQ_${sys}_$index"}++;
		    
		    push( @{$cmds{$sys}}, $o );
		} elsif( $o =~ /^L (\d+) (\d+)/ ) {
		    $form->{"ORD_LO_$1"} = $2;
		    $carrier{$1} = $2;
		    push( @{$cmds{$1}}, $o );
		} elsif( $o =~ /^N (\d+) (.*)/ ) {
		    $form->{"ORD_REN_$1"} = $2;
		    $renames{$1} = $o;
		    push( @{$cmds{$1}}, $o );
		} elsif( $o =~ /^R (\d+) (.*)/ ) {
		    $form->{"ORD_RE_$1"} = $2;
		    push( @{$cmds{$1}}, $o );
		} elsif( $o =~ /^U (\d+)/ ) {
		    $form->{"ORD_UL_$1"} = 1;
		    $uncarrier{$1} = 1;
		    push( @{$cmds{$1}}, $o );
		} elsif( $o =~ /^F (\d+) (\d+) (\d+)/ ) {
		    my( $firing_ship, $strength, $target_ship ) = ( $1, $2, $3 );
		    my $fire_idx = $s2fire_idx{$firing_ship} || 0;
		    $form->{"ORD_ST_${firing_ship}_$fire_idx"} = $target_ship;
		    $form->{"ORD_SS_${firing_ship}_$fire_idx"} = $strength;
		    $s2fire_idx{$firing_ship}++;
		    push( @{$cmds{$firing_ship}}, $o );
		} elsif( $o =~ /^M (\d+) (\d+)/ ) {
		    my( $ship_id, $sys_id ) = ( $1, $2 );
		    my $ship = G::Base::fetch( $ship_id );

		    if( $ship->get_prototype( 'name' ) eq 'Scout' ) {
			my $move_idx = $s2move_idx{$ship_id} || 0;
			$form->{"ORD_SM_${ship_id}_$move_idx"} = $sys_id;
			$s2move_idx{$ship_id}++;
		    } else {
			$form->{"ORD_PM_$ship_id"} = $sys_id;
		    }
		    push( @{$cmds{$ship_id}}, $o );
		} else {
		    print "Content-Type: text/html\n\n<pre>".Data::Dumper->Dump( [$o,':('] )."</pre>";
		}
	    } #each order
	}

	####################
	#         display

	my $panel_x = 816;
	my $panel_y = 700;

	my $murl = "StellarExpanse/data/maps/$game->{ID}/".$game->get_turn()."/$player->{ID}";
	my $mapurl = "$murl.png";
	my $jsurl = "$murl.js";

	my $rus = $player->get_rus( );
	my $tech = $player->get_tech( );

	my $maps = $player->get_maps( );
	my $title2id = $game->get_flavor()->get_prototypes();

	# 
	# Translate data into javascript.
	# 
	my $head = qq~
<link rel="stylesheet" type="text/css" href="StellarExpanse/gapher.css" />
<script src="StellarExpanse/tools.js"></script>
<script src="$jsurl"></script>
<script>
   var player = Object();
   var ships = Array(); // id -> data structure
   var map = Array(); // id -> data structure
   var form = Object(); //translate the form to this.
~;
	# form
	for my $key (keys %$form) {
	    $head .= "form['$key'] = '$form->{$key}';\n";
	}

	$head .= qq~
 var planetId2info = Array();
~;
	for my $pid (keys %$maps) {
	    my $node = $maps->{$pid};
	    my $sect = $node->get_system();
	    $head .=  "planetId2info[$pid] = Object();";
	    $head .=  join("\n", map { "planetId2info[$pid]['$_'] = '".$sect->get_state($_)."';\n" } (qw/name/));
	    $head .=  "var other = Object();\n";
	    $head .=  "planetId2info[$pid]['other_ships'] = other;\n";
	    my $oships = $node->get_state( 'their_ships', [] );

	    $head .=  join("\n",map { "other[other.length] = '$_->{ID}'\n" } @$oships) if $oships;
	    my $mships = $node->get_state( 'my_ships', [] );
	    $head .=  "var mine = Object();\n";
	    $head .=  "planetId2info[$pid]['my_ships'] = mine;\n\n";
	    $head .=  join("\n",map { "mine[mine.length] = '$_->{ID}'\n" } @$mships) if $mships;
	    $head .=  "var canBuild = Array();\n";
	    $head .=  "planetId2info[$pid]['canBuild'] = canBuild;\n";
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

	    $head .=  "\nvar idx = canBuild.length;\ncanBuild[idx] = Object();\n";
	    $head .= "canBuild[idx]['name'] = 'None'\n";

	    for my $info (@can_build_size) {
		$head .=  "\nvar idx = canBuild.length;\ncanBuild[idx] = Object();\n";
		$head .=  join("\n",map { "canBuild[idx]['$_'] = '".$info->get($_)."';\n" } (qw/name tech_level damage_control jumps design_id cost targets self_destruct attack_beams defense size racksize type/) );
	    }
	    
	} #each planet

	$head .= qq~
 var img_h;
 var img_w;

 function init() { 
    set_dimentions();
    img_w = img_w + 0;
    img_h = img_h + 0;
    var x_max = 800; var y_max = 700;
    var x_panel = img_w < x_max ? img_w : x_max;
    var y_panel = img_h < y_max ? img_h : y_max;

    var img_div = el('image');
    //add image and scale controls
    var canv = ce('canvas');
    img_div.appendChild( canv );
    canv.id = 'canvas';
    canv.width = x_panel;
    canv.height = y_panel;
    canv.style.border='solid 1px';
    var canv_ctrl = make_canvas( canv );

    var ip = make_image_panel( canv_ctrl, '$mapurl', 0, 0, img_w, img_h, x_panel, y_panel );
    canv_ctrl.add_control( ip );
    init_map( ip );
    var fitx = x_max / .75;
    var fity = y_max / .75;
    
    var ul = ce('ul');
    var li;
    li = ce('li'); li.appendChild( ctn('Click on a system to control it' ) );
    ul.appendChild( li );
   
    img_div.appendChild( ce('br') );
    img_div.appendChild( ul );

    if( img_w < x_max && img_h < y_max ) {
      ip.can_pan = false;
      ip.scale = 1;
//    } else if( img_w < fitx && img_h < fity ) {
//      ip.can_pan = false;
//      ip.scale = x_panel/img_w;
    } else {
      li = ce('li'); li.appendChild( ctn('You can pan the map around by dragging it' ) );
      ul.appendChild( li );
      li = ce('li'); li.appendChild( ctn('Grab the triangle below to zoom the map in and out' ) );
      ul.appendChild( li );

      var zcanv = ce('canvas');
      img_div.appendChild( zcanv );
      zcanv.id = 'zcanv';
      zcanv.width = 200;
      zcanv.height = 50;
      zcanv.style.border='solid 1px';
      var zcanv_ctrl = make_canvas( zcanv );
      var zoom = make_zoom( zcanv_ctrl, ip, 10, 10, 180, 30 );
      zcanv_ctrl.add_control( zoom );
    }
~;
    for my $pid (keys %$maps) {
	my $node = $maps->{$pid};
	my $sect = $node->get_system();
	my $own =  $sect->get_state( 'owner' );
	if( $own && $own->{ID} == $player->{ID} ) {
	    my( @builds ) = grep { $_ =~ /ORD_BSN_$pid\_/ } (keys %$form);
	    $head .= join("\n", map { "add_build_for_system($pid);" } (@builds) );
	    $head .= "add_build_for_system($pid);" unless @builds;
	}
    } #each pid


	if( $form->{last_system} ) {
	    $head .= "show_system( $form->{last_system} );";
	}
	$head .= qq~
    canv_ctrl.draw(); 
 } //init

 var builds = Array();
 function add_build_for_system( system_id ) {
    if( builds[system_id] == null ) {
       builds[system_id] = 0;
    }
    var idx = builds[system_id];
    builds[system_id]++;
    var sel = ce('select');
    sel.name = 'ORD_BSS_' + system_id + '_' + idx;
    var can_build = planetId2info[system_id]['canBuild']; 

    for( var i=0; i<can_build.length; i++ ) {
      var opt = ce('option');
      if( form['ORD_BSS_'+system_id+'_'+idx] != null && 
          (form['ORD_BSS_'+system_id+'_'+idx]+0)>0 &&
          (0+form['ORD_BSS_'+system_id+'_'+idx]) == (0+can_build[i]['design_id']) ) {
         opt.selected = true;
      }
      opt.value = can_build[i]['design_id'];
     if( can_build[i]['name'] == 'None' ) {
         opt.appendChild( ctn(can_build[i]['name'] ) );
     } else {
         opt.appendChild( ctn(can_build[i]['name']+'/'+can_build[i]['attack_beams']+'/'+can_build[i]['defense']+'/'+can_build[i]['size']+'/'+can_build[i]['cost']+'/'+can_build[i]['racksize'] ) );
       }     
       sel.appendChild( opt );
    }

    var namefld = ce('input');
    namefld.type = 'text';
    namefld.name = 'ORD_BSN_'+system_id+'_'+idx;
    if( form[namefld.name] != null ) {
      namefld.value = form[namefld.name];
    } else {
      namefld.value = '';
    }
    
    var quanfld = ce('input');
    quanfld.type = 'text';
    quanfld.value = "1";
    quanfld.name = 'ORD_BSQ_'+system_id+'_'+idx;
    if( form[quanfld.name] != null ) {
       quanfld.value = form[quanfld.name];
    } else {
       quanfld.value = 1;
    }    

    add_row( system_id + '_build_table', Array( sel, namefld, quanfld ) );
 }

 function show_system( system_id ) {
     show( 'noship', false );
     show( 'unknown_system', false );
     el('last_system').value = system_id;
~;
     for my $pid (keys %$maps) {
	 $head .= "show( '$pid\_system', false );\n";
     }
     $head .= qq~
	 if( el( system_id + '_system' ) != null ) {
	     show( system_id + '_system', true );
         } else {
	     show( 'unknown_system', true );
         }
	 return;
 } //show_system
~;
	$head .= '</script>';

	$self->open_html( {
	    acct => $player->get_account(),
	    msg => , $msg,
	    title => 'gapher',
	    head => $head,
			  } );
	print "<div id=readybox>";
	if( $player->get_state('ready') ) {
	    print '<span style="background-color:green">Ready for next turn</span><BR>';
	    print '<input id="creadybox" type=checkbox name="set_not_ready"> <label for="creadybox">Set to not ready</label><br>';
	} else {
	    print '<span style="background-color:red;">Not Ready for next turn</span><BR>';	    
	    print '<input id="creadybox" type=checkbox name="set_ready"> <label for="creadybox">Set to ready</label><br>';
	}
	print "<input type=submit value=Update>";
	print "</div>";
	print "<div id=players>";

	print "</div>";

	print "<hr>";
	print "<div id=info>";
	print "<BR>Turn : ".$game->get_turn()."<BR>";
	print "<BR>Tech : ".$player->get_state( 'tech' )."<BR>";
	print "<BR>RUS  : ".$player->get_state('rus')."<BR>";
	my $messages = $player->get_state('messages');
	print '<div style="border:solid 1 px"><h3>Messages</h3><ul>'.join( '', map { "<li>$_->{msg}</li>" } @$messages ).'</ul></div>';
	print qq~<div style="border:solid 1 px"><h3>Orders</h3><ul>~.join('',map { "<li>$_</LI>" } @ords)."</ul></div>";
	print "</div>";
#	print "<img src=$mapurl><BR>";

	print qq~<DIV id=image></DIV>~;

	print qq~<BR>
<div name=alerts style=display:none>
<BR><input type=text size=150 id=alert>
<BR><input type=text size=150 id=alert2>
<BR><input type=text size=150 id=alert3>
</div>
<HR>
<input type=hidden id=last_system name=last_system value=0>
<div id=noship name=noship>Click on a system to get data and give orders for it</div>
<div id=unknown_system name=unknown_system style=display:none>This system is unexplored</div>
~;
	for my $pid (keys %$maps) {
	    my $node = $maps->{$pid};
	    my $sect = $node->get_system();
	    my $own = $sect->get_state( 'owner' );
	    my $own_name = 'unclaimed';
	    my $am_owner = 0;
	    my $ships = $sect->get_state( 'ships' );
	    my @mine = grep { $_->get_state( 'owner' ) != $player->{ID} } @$ships;
	    if( $own ) {
		if( $own->{ID} == $player->{ID} ) {
		    $own_name = $own->get_name();
		    $am_owner = 1;
		} else {		    
		    $own_name = $self->href("?session=$sess&player_page=$own->{ID}",$own->get_name());
		}
	    }

	    # ---------- different UI styles ---------
	    #
	    #
	    # the cases are 
	    #     system is owned
	    #     have ship in system
	    #     system was visited once
	    #     system was not visited
	    #
	    
	    print "<div id=$pid\_system style='display:none'>";
	    
	    print "<fieldset><legend>".$sect->namestr()."</legend>";

	    if( $am_owner ) {
		my $tname = $renames{$pid} || $sect->get_state('name');
		print qq~<input type=hidden name=HORD_REN_$pid value="$tname">~;
		print "<table><tr>".join('',map { "<th>$_</th>" } qw/ID owner production maxsize rename/).'</tr>';
		print '<tr>';
		print join('', map { "<td>$_</td>" } ( $pid,
						       $own_name, 
						       $sect->get_state( 'currprod' ).'/'.$sect->get_maxprod(),
						       $sect->get_state( 'buildcap' ),
						       "<input type=text name=ORD_REN_$pid id=$pid\_sys_rename value=\"$tname\">",
			   ));
		print '</tr></table>';
	    } elsif( @mine ) {
		if( $own ) {
		    print 'owner : '.$own->get_name()."<BR>";
		    print 'production : '.$sect->get_state( 'currprod' )."<BR>";
		} else {
		    print 'owner : not owned<BR>';
		}
		print 'max production : '.$sect->get_maxprod()."<BR>";
	    } else {

	    }


	    
	    # owner, production, max build size
	    # builds
	    # enemy ships        
	    my @others = grep { $_->get_state( 'owner' )->{ID} != $player->{ID} } @$ships;
	    if( @mine || $am_owner ) { #only show known enemy ships if you are the owner or have ships that can see
		if( @others ) {
		    print "<h3 class=warn>Enemy Ships in this sector</h3><blockquote>";
		    print "<table id=$pid\_threat_table><TR>".join('',map {"<TH>$_</TH>" } qw/Owner Ship Type Health Targets Beams Move/ );
		    print "</tr>";
		    for my $o (@others) {
			print "<TR>".join('',map { "<TD>".$o->get_state( $_ )."</TD>" } qw/owner name/)."</tr>";
			print "<TR>".join('',map { "<TD>".$o->get_prototype( $_ )."</TD>" } qw/type defense targets attack_beams jumps/)."</tr>";
		    }
		    print "</table>";
		    print "</blockquote>";
		}
	    }
	    
	    # my ships in sector
	    #     name,id,type,attack,health/defense,size,targets,beams,maxmove,rackspace
	    #     repair
	    if( @mine ) {
		print "<h3 class=warn>My Ships in this sector</h3><blockquote>";
		print "<table id=$pid\_ship_table><TR>".join('',map {"<TH>$_</TH>" } qw~Ship Type Rack Health Targs/Beams Move ~ );
		print "<TH>Fire</TH>" if @others;
		print join('', map { "<TH>$_</TH>" } qw/Repair Load Unload/ );
		print "</TR>";
		for my $o (@mine) {
		    my $mtarget;
		    my $repair_order;
		    for my $ord (@{$cmds{$o->{ID}}}) {
			if( $ord =~ /^R\s+\d+\s+(\d+)/ ) {
			    $repair_order = $1;
			}
		    } 
		    if( $o->get_prototype( 'jumps' ) > 0 ) {

			if( $o->get_prototype( 'name' ) eq 'Scout' ) {
			    my $mtargs = find_within( $sect, $maps, $o->get_prototype('jumps'), 1 );
			    my( @scout_moves ) = grep { /^\s*M\s+$o->{ID}\s+\d+/ } @ords;

			    for( my $i=0; $i<$o->get_prototype( 'jumps' ); ++$i ) {
				my $none_select = $scout_moves[$i] ? '' : ' selected';
				$mtarget .= '<br>' if $i > 0;
				$mtarget .= "<select name=ORD_SM_$o->{ID}_$i><option $none_select>none</option>";
				
				my( $aa, $sd, $w ) = split( /\s+/, $scout_moves[$i] );
				for my $targ (sort { lc($a->namestr()) cmp lc($b->namestr()) } @$mtargs ) {
				    my $chosen = $w == $targ->{ID} ? 'selected' : '';
				    $mtarget .= qq~<option value="$targ->{ID}" $chosen>~.$targ->namestr()."</option>";
				}
				$mtarget .= "</select>";
			    }
			} else {
			    my $mtargs = find_within( $sect, $maps, $o->get_prototype('jumps') );
			    $mtarget = qq~<select name="ORD_PM_$o->{ID}"><option value="">none</option>~.
				join('',map { qq~<option value="$_->{ID}"~.($_->{ID}==$form->{"ORD_PM_$o->{ID}"}?' selected':'').">".( $_->get_state('name') )."</option>" } @$mtargs)."</select>";
			}
		    } else {
			# no move
		    }
		    print "<TR>";
		    print join('',map { "<TD>".$o->get_state($_)."</TD>" } qw/name/);
		    print join('',map { "<TD>".$o->get_prototype($_)."</TD>" } qw/name rack/);
		    printf "<TD>%s</td>", $o->get_state('health').'/'.$o->get_prototype('defense');
		    printf "<TD>%s</td>", $o->get_prototype('targets').'/'.$o->get_prototype('attack');
		    if( $mtarget ) {
			print "<TD>$mtarget</td>";
		    } else {
			printf "<TD>%s</td>", $o->get_prototype('jumps');
		    }
		    
		    #fire control
		    if( @others ) {
			my( @targ_ord, @f_ords );
			for my $ord (@{$cmds{$o->{ID}}}) {
			    if( $ord =~ /^\s*F\s+\d+\s+(\d+)\s+(\d+)/ ) {
				my( $strength, $targ ) = ( $1, $2 );
				push( @targ_ord, [$targ, $strength] );
			    }
			}
			my $max = $o->get_prototype('targets') > @others ? @others : $o->get_prototype('targets');
			for my $idx (1..$max) {
			    my $current_order = shift(@targ_ord);
			    my $fval = $current_order ? $current_order->[1] : undef;
			    push( @f_ords, qq~<SELECT name=ORD_ST_$o->{ID}_$idx><option>none</option>~.join('',map { "<option ".($current_order && $_->{ID} == $current_order->[0] ? ' selected' : '')." value=$_->{ID}>$_->get_state('owner')->get_state('name')/$_->get_state('name') ($_->{ID})</option>" } @others )."</select> <INPUT TYPE=text name=ORD_SS_$o->{ID}_$idx value=\"$fval\">" );
			}
			print '<td>'.join('',@f_ords).'</td>';
		    } #if enemy ships

		    #load
		    my $load_box = ' ';
		    my $rackspace = $o->get_state( 'free_rack' );

		    if( $rackspace > 0 ) {
			my @loadable = grep { $_->get_prototype('size') <= $rackspace && ref( $_->get_state('location') ) eq 'G::ARCADE::StellarExpanse::Sector' } @mine;

			$load_box = 'not enough room';
			$load_box = 'nothing to load' if @mine == 1;
			if( @loadable ) {
			    my( %loaded ) = map { $_ => 1 } split(/\0/,$carrier{$o->{ID}});
			    $load_box = join('<br>',map { qq~<input type="checkbox" 
							      value="$_->{ID}"
							      name="ORD_LO_$o->{ID}"
							      ~.( $loaded{$_->{ID}} ? ' checked' : '').
							      "> ".$_->get_state('name')." ($_->{ID})" }
					     @loadable );
			} 
		    }
#unload
		    my $unload_box = ' ';
		    if( $o->get_state( 'carried' ) ) {
			$unload_box = join('<br>', map { qq~<input type=checkbox name="ORD_UL_$_->{ID}" ~.( $uncarrier{$_->{ID}} ? ' checked' : '' )."> ".$_->get_state('name')." ($_->{ID})" }
					   (@{$o->get_state( 'carried' )}) );
		    }

		    print qq~<TD><input type=text name=ORD_RE_$o->{ID} size=3 value="$repair_order"></TD>~;
		    print "<TD>$load_box</TD>";
		    print "<TD>$unload_box</TD>";
		    print "</tr>";
		} #each of my ships
		print "</table></blockquote>";
	    } #if there are my ships

	    if( $am_owner ) {
		print "<P><h3>Builds</h3>";
		print "<table id=$pid\_build_table><tr><th>Item</th><th>Name</th><th>Quantity</th></tr></table>";    
		print "<a href='javascript:void(0)' onclick='add_build_for_system($pid);'>build more</a>";
	    }
	    print "</fieldset>";
	    print "</div>";
	} #each system
	print "<input type=hidden name=HORD value=1>";
	print "<input type=submit value=Update>";
    }
    else {
	$self->check_updates( $form );
	$self->print_html_open( "", $player->get_account(), $msg );
	if( $status ne $G::Game::WAITING_FOR_PLAYERS ) {
	    print "<BR><BR>Available Actions : ".$self->href("javascript:void(0)", "leave game", qq~onclick='confirm_link( "really leave game?", "?leave_game=$game->{ID}&session=$sess" );'~ );
	}
	print "<BR>".$self->href("?session=$sess","back to lobby" );
	print "<BR><hr>";
	print "<h1>".$game->get_name()."</h1>";
	print "<blockquote>";
	print "Description : ".$game->get_description().'<br>';
	print "</blockquote>";
	print "<HR>";
	print "<h2>Turn ".$game->get_turn()."</h2>";
	print "Status : $status<BR>";
	print $self->href("?session=$form->{session}&join_game=$game->{ID}","refresh");
	print "<blockquote>";

    }
    print "<input type=hidden name=session value=$sess>";
    print "<input type=hidden name=join_game value=$game->{ID}>";
    print "<input type=hidden name=turn value=".$game->get_turn().">";

    $self->print_html_close();
    G::Base::do_query("COMMIT");
} #play_game


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

    my $cons = $a->get_links();

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

sub init_js_vars {
    my( $form, $player, $game ) = @_;
    my $buff = '';
    $buff .= '   var form = Object(); //translate the form to this';
    # form
    for my $key (keys %$form) {
	$buff .= "form['$key'] = '$form->{$key}';\n";
    }

    # ships loaded. 
    my $ships = $player->get_state( 'ships' );
    for my $ship (@$ships) {
	my $loc = $ship->get_state( 'location' );
	# this relies on the fact that the location doesn't have loaded ships as 'my ships'
	if( ref $loc eq 'G::ARCADE::StellarExpanse::StellarExpanse' ) {
	    my $carloc = $loc->get_state( 'location' );
	    $buff .= "ships[$ship->{ID}] = Object();\n";
	    $buff .= "ships[$ship->{ID}]['location'] = $carloc->{ID};\n";
	    $buff .= "ships[$ship->{ID}]['loaded'] = true;\n";
	    $buff .= "ships[$ship->{ID}]['owner'] = '".$player->get_name()."';\n";
	    for my $key (qw/name health/ ) {
		$buff .= "ships[$ship->{ID}]['$key'] = '".$ship->get_state($key)."';\n";
	    }
	    $buff .= "ships[$ship->{ID}]['type'] = '".$ship->get_prototype('name')."';\n";
	    for my $key (qw/tech_level damage_control jumps design_id cost targets self_destruct attack_beams defense size racksize type/ ) {
		$buff .= "ships[$ship->{ID}]['$key'] = '".$ship->get_prototype($key)."';\n";
	    }	    
	} 
    } #each ship
    

    # map and ships
    my $map = $player->get_state( 'maps' );
    for my $s_id (keys %$map) {
	$buff .= "map[$s_id] = Object();\n";
    }
    for my $s_id (keys %$map) {
	my $node = $map->{$s_id};
	my $sect = $node->get_sector();
	my $own = $sect->get_state( 'owner' );
	$buff .= "map[$s_id]['name'] = '".$sect->get_state('name')."';\n";
	if( $own->{ID} == $player->{ID} ) {
	    $buff .= "map[$s_id]['mine'] = true;\n";
	} else {
	    $buff .= "map[$s_id]['mine'] = false;\n";
	}
	$buff .= "map[$s_id]['seen_production'] = ".$node->get_state('seen_production').";\n";
	$buff .= "map[$s_id]['seen_owner'] = ".$node->get_state('seen_owner').";\n";
	$buff .= "map[$s_id]['maxprod'] = ".$sect->get_maxprod().";\n";
	$buff .= "map[$s_id]['connections'] = Array();\n";

	my $links = $sect->get_links();
	for my $link_id (keys %$links) {
	    $buff .= "map[$s_id]['connections'][map[$s_id]['connections'].length] = $link_id;\n";
	}

	my $my_ships = $node->get_state( 'my_ships' );
	my $their_ships = $node->get_state( 'their_ships' );
	for my $ship ( @$my_ships, @$their_ships ) {
	    my $owner = $ship->get_state( 'owner' );
	    $buff .= "ships[$ship->{ID}] = Object();\n";
	    $buff .= "ships[$ship->{ID}]['location'] = $sect->{ID};\n";
	    $buff .= "ships[$ship->{ID}]['loaded'] = false;\n";		
	    $buff .= "ships[$ship->{ID}]['owner'] = '".$owner->get_name()."';\n";
	    for my $key (qw/name health/ ) {
		$buff .= "ships[$ship->{ID}]['$key'] = '".$ship->get_state($key)."';\n";
	    }
	    $buff .= "ships[$ship->{ID}]['type'] = '".$ship->get_prototype('name')."';\n";
	    for my $key (qw/tech_level damage_control jumps design_id cost targets self_destruct attack_beams defense size racksize type/ ) {
		$buff .= "ships[$ship->{ID}]['$key'] = '".$ship->get_prototype($key)."';\n";
	    }
	    
	}
	
	$buff .= "map[$s_id]['my_ships'] = Array();\n";
	for my $ship ( @$my_ships ) {
	    $buff .= "map[$s_id]['my_ships'][map[$s_id]['my_ships'].length] = $ship->{ID};\n";
	}
	$buff .= "map[$s_id]['their_ships'] = Array();\n";
	for my $ship ( @$their_ships ) {
	    $buff .= "map[$s_id]['their_ships'][map[$s_id]['their_ships'].length] = $ship->{ID};\n";
	}		

    } #each map entry

    # player 
    $buff .= "player['messages'] = Array();\n";
    $buff .= "player['turn'] = $game->get_turn();\n";
    $buff .= "player['messages'] = Array();\n";
    my $messages = $player->get_state( 'messages' );
    for my $m (@$messages) {
	$buff .= "player['messages'][player['messages'].length] = '$m';\n";
    }
    $buff .= "player['systems'] = Array();\n";
    my $systems = $player->get_state( 'systems' );
    for my $s (@$systems) {
	$buff .= "players['systems'][players['systems'].length] = map[$s->{ID}];\n";
    }
    $buff .= "player['ships'] = Array();\n";
    for my $ship (@$ships) {
	$buff .= "players['ships'][players['ships'].length] = ships[$ship->{ID}];\n";
    }	
    return $buff;
} #init_js_vars

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut
