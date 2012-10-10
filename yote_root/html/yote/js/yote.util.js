$.yote.util = {
    ids:0,
    next_id:function() {
        return 'yidx_'+this.ids++;
    },
    stage_text_field:function(attachpoint,yoteobj,fieldname) {
        var val = yoteobj.get(fieldname);
        var idname = this.next_id();
        attachpoint.append( '<input type=text id=' + idname + '>' );
        $( '#'+idname ).val( val );
        $( '#'+idname ).keyup( (function (o,k,id,initial) {
            return function(e) {
                var newval = $(id).val();
                o._stage(k,newval);
                if( initial != newval || o._is_dirty(k)) {
                    $(id).css('background-color','lightyellow' );
                } else {
                    $(id).css('background-color','white' );
                }
            }
        } )(yoteobj,fieldname,'#'+idname,val) );
        return $( '#' + idname );
    }, //stage_text_field

    stage_textarea:function(args) {
        var attachpoint = args['attachpoint'];
        var yoteobj   = args['yoteobj'];
        var fieldname = args['fieldname'];
        var cols      = args['cols'];
        var rows      = args['rows'];
        var as_list   = args['as_list'];

        var idname    = this.next_id();
        attachpoint.append( '<textarea cols='+cols+' rows='+rows+' id=' + idname + '></textarea>' );
        var val;
        if( as_list == true ) {
            var a = Array();
            for( var i=0; i < yoteobj.length(); ++i ) {
                a.push( yoteobj.get( i ) );
            }
            val = a.join( '\n' );
            $( '#'+idname ).attr( 'value', val );
        } else {
            val = yoteobj.get(fieldname);
            $( '#'+idname ).attr( 'value', val );
        }
        $( '#'+idname ).keyup( (function (o,k,id,initial) {
            return function(e) {
                var newval = $(id).attr('value');

                if( initial != newval || o._is_dirty(k)) {
                    $(id).css('background-color','lightyellow' );
                } else {
                    $(id).css('background-color','white' );
                }

                if( as_list == true ) {
                    newval = newval.split( /\r\n|\r|\n/ );
                    for( var nk in newval ) {
                        o._stage( nk, newval[nk] );
                    }
                }
                else {
                    o._stage(k,newval);
                }
            }
        } )(yoteobj,fieldname,'#'+idname,val) );
        return $( '#' + idname );
    }, //stage_textarea

    /*
      yote_obj/yote_fieldname 
      - object and field to set an example from the list
      list_fieldname - field in the list objects to get the item name for.
    */
    stage_object_select:function(args) {
        var attachpoint    = args['attachpoint'];
        var yote_obj       = args['yote_obj'];
        var yote_fieldname = args['yote_fieldname'];
        var yote_list      = args['yote_list'];
        var list_fieldname = args['list_fieldname'];
        var include_none   = args['include_none'];
        var current        = yote_obj.get( yote_fieldname );

        var current_id = typeof current === 'undefined' ? undefined : current.id;
	var idname = this.next_id();
        attachpoint.append( '<SELECT id='+idname+'>' + (include_none == true ? '<option value="">None</option>' : '' ) + '</select>' );
        for( var i=0; i<yote_list.length(); ++i ) {
            var obj = yote_list.get( i );
            var val = obj.get( list_fieldname );
            $( '#' + idname ).append( '<option value="' + obj.id + '" ' 
                                      + (obj.id==current_id ? 'selected' :'') + '>' + val + '</option>' );
            $( '#' + idname ).click(
                ( function(o,k,id,initial) {
                    return function() {
                        var newid = $(id).val();
                        o._stage(k,undefined);
                        if( initial != newid || o._is_dirty(k) ) {
                            $(id).css('background-color','lightyellow' );
                        } else {
                            $(id).css('background-color','white' );
                        }
                    }
                } )(yote_obj,yote_fieldname,'#'+idname,current_id)
            );
        }
    }, //stage_object_select

    make_select:function(attachpoint,list,list_fieldname) {
	var idname = this.next_id();
        attachpoint.append( '<select id='+idname+'></select>' );
	for( var i in list ) {
	    var item = list[i];
	    $( '#'+idname ).append( '<option value='+item.id+'>'+item.get(list_fieldname)+'</option>' );
	}
	return $( '#' + idname );
    },
    make_login_box:function(args) {
	var target       = args['target'];
	var logged_in_f  = args['on_login']    || args['on_in'];
	var created_f    = args['on_register'] || args['on_in'];
	var recover_f    = args['on_recover']  || args['on_in'];
	var logged_out_f = args['on_logout'];
	var app       = args['for_app']

	var do_login = args[ 'login_box' ] || "<div style=display:none id=y_login_div>" +
	    "<table><tr><td>Handle</td><td><input class=login id=login type=text></td>" +
	    "</tr><tr><td>Password</td><td><input class=login id=password type=password>" +
	    "</td></tr></table><br>" +
	    "<input class=login id=login_submit type=submit value=Login>" +
	    " <a href='#' id=register_link>Register</a>" +
	    " <a href='#' id=forgot_link>Forgot</a>" +
	    "</div>";

	var not_logged_in = args[ 'notloggedin_box' ] || "<div style=display:none id=y_not_loggedin>" +
	    "Not logged in. <a href='#' id=login_link>Login</a> &nbsp;" +
	    "<a href='#' id=register_link>Register</a>" +
	    "</div>";

	var register = args[ 'register_box' ] || "<div style=display:none id=y_register_account>" +
	    "<table><tr><td>Handle</td><td><input class=register id=login type=text></td>" +
	    "</tr><tr><td>Email</td><td><input class=register id=email type=text>" +
	    "</tr><tr><td>Password</td><td><input class=register id=password type=password>" +
	    "</td></tr></table>" + 
	    "<input id=register_submit type=submit value=Register> " +
	    "  <div id=register_login_link_div><a href='#' id=login_link>Login</a></div>" +
	    "</div>"

	var change_account = args[ 'change_box' ] || "<div style=display:none id=y_change_account>" + 
	    "Change Account Settings<BR>" + 
	    "<table>" + 
	    "<tr><td>Current Password</td><td><input type=password id=old_pw></td>" +
	    "<tr><td>Email</td><td><input id=change_email></td><td><button type=button id=change_email_b>Update Email</button> " +
	    "<tr><td colspan=3><hr></td></tr>" + 
	    "<tr><td>New Password</td><td><input type=password id=change_pw1></td>" +
	    "<tr><td>New Password (again)</td><td><input type=password id=change_pw2></td><td><button type=button id=change_password_b>Update Password</button></td></tr> " +
	    "</table>" + 
	    "<BR><a href='#' id=change_done>Done</a>" +
	    "</div>";

	var recover = args[ 'recover_box' ] || "<div style=display:none id=y_recover_account>" +
	    "Email <input class=recover id=email> " +
	    "<input id=recover_submit type=submit value=Recover>" +
            "<a href='#' id=login_link>Login</a>" + 
	    "</div>";

	var logged_in = args[ 'loggedin_box' ] || "<div style=display:none id=y_logged_in>" +
	    "Logged in as <span class=logged_in id=handle></span> [<a id=change_link href='#'>update</a> ]<BR>" +
	    "[<a id=logout_link href='#'>logout</a>]" +
	    "</div>"

	$(target).empty();
	$(target).append( "<span id=login_msg_outerspan style=display:none><span id=login_msg_span class=warning></span>" +
			  "<BR></span>" +
			  do_login + 
			  not_logged_in +
			  register +
			  change_account +
			  recover +
			  logged_in			  
			);
	var message = function( msg ) {
            if( typeof msg === 'string' ) {
	        $( target + ' #login_msg_span').empty();
	        $( target + ' #login_msg_span').append( msg );
	        $( target + ' #login_msg_outerspan').show();    
	    } else {
	        $( target + ' #login_msg_span').empty();
	        $( target + ' #login_msg_outerspan').hide();
            }
	}
	var install_function = function( f ) { return function() { f(); } }
	var on_enter = function(f) { return function(e) { if(e.which == 13 ) { f(); } } }
	var to_login = function(msg) {
	    message( msg );
	    $( target + ' > div ' ).hide();
	    $( target + ' > div#y_login_div' ).show();
	}
	var to_recover = function() {
	    $( target + ' > div ' ).hide();
	    $( target + ' > div#y_recover_account' ).show();
	}
	var to_register = function(msg) {
	    message( msg );
	    $( target + ' > div ' ).hide();
	    $( target + ' > div#y_register_account' ).show();
	}
	var to_logged_in = function(name,msg) {
            message(msg);
	    $( target + ' > div ' ).hide();
	    $( target + ' .logged_in#handle' ).empty();
	    $( target + ' .logged_in#handle' ).append(name);
	    $( target + ' > div#y_logged_in' ).show();                
	    logged_in_f();
	}

	var to_change = function() {
	    $( target + ' > div ' ).hide();
	    $( target + ' > div#y_change_account ' ).show();
	    $( target + ' #change_email' ).val( $.yote.login_obj.get('email' ) );
	    $( target + ' > #change_email' ).attr( 'disabled', false );	
	    $( target + ' > #change_email' ).prop( 'disabled', false );	
	}

	var do_login = function() {
	    $.yote.login( $( target + " .login#login").val(), $(target + " .login#password").val(),
			  function(data) { //pass
			      to_logged_in($.yote.login_obj.get('handle'));
			      // note the following line will work but is not closure safe yet.
			      //if( typeof logged_in_f === 'function' ) { logged_in_f(); }
			  },
			  function(data) { //fail
			      to_login(data);
			  }
			);
	}
	var do_register = function() {

            if( $( target + " .register#password").val().length > 2 ) {
	        $.yote.create_login( $( target + " .register#login").val(),
				     $( target + " .register#password").val(),
				     $( target + " .register#email").val(),
				     function(data) { //pass
					 to_logged_in($.yote.login_obj.get('handle'),"Created Account");
					 if( typeof created_f === 'function' ) { created_f(); }
				     },
				     
				     function(data) { //fail
					 to_register(data);
				     }
				   );     
            } else {
                to_register("password too short");
            }           
	}
	var do_recover = function() {
	    $.yote.fetch_root().recover_password( { e : $( target + ' .recover#email' ).val(), 
						    u : window.location.href,
						    t : location.protocol + "//" + location.hostname +
						    (location.port ? ':'+location.port: '') + "/yote/reset.html"
						  },
						  function(d) {
						      to_login( "sent recovery email" );
						  },
						  function(d) {
						      message(d);
						  }
					);
	    if( typeof recover_f === 'function' ) { recover_f(); }
	}

	var logout = function() {
	    $( target + ' > div ' ).hide();
            var rootapp = $.yote.fetch_root();

            if( rootapp.number_of_accounts() > 0 ) {
		$( target + ' > div#y_not_loggedin' ).show();
		$( target + ' #register_login_link_div' ).show();
            } else {
                $( target + ' > div#y_register_account' ).show();
		$( target + ' #register_login_link_div' ).hide();
                message( "Create Initial Root Account" );
            }
	    $( target + ' #password' ).val('');
	    $.yote.fetch_root().logout();
	    if( typeof logged_out_f === 'function' ) { logged_out_f(); }
	}

	//link actions
        var nada = function() {};

	$( target + ' #login_link').click( install_function(to_login || nada ) );
	$( target + ' #register_link').click( install_function(to_register || nada) );
	$( target + ' #logout_link').click( install_function(logout || nada) );
	$( target + ' #forgot_link').click( install_function(to_recover || nada) );
	$( target + ' #change_link').click( install_function(to_change || nada) );

	//button actions
	$( target + ' #login_submit').click( install_function(do_login || nada) );
	$( target + ' .login#login,' + target + ' .login#password' ).keypress( on_enter(do_login) );
	$( target + ' #register_submit').click( install_function(do_register || nada) );
	$( target + ' .register#login,' + target + ' .register#password,' + target + ' .register#email' ).keypress( on_enter(do_register) );
	$( target + ' .recover#email' ).keypress( on_enter(do_recover) );
	$( target + ' #recover_submit' ).click( install_function(do_recover || nada) );

	$( target + ' #change_email_b' ).click( function() {
	    $.yote.login_obj.reset_email( { pw : $( target + ' #old_pw' ).val(),email : $( target + ' #change_email' ).val() },  function(succeed) { message( succeed ) }, function(fail) { message( fail ) } );
	} );
	$( target + ' #change_password_b' ).click( function() {
	    $.yote.login_obj.reset_password( { op : $( target + ' #old_pw' ).val(), p : $( target + ' #change_pw1' ).val(), p2 : $( target + ' #change_pw2' ).val() },  function(succeed) { message( succeed ) }, function(fail) { message( fail ) } );
	} );
	$( target + ' #change_done' ).click( function() { if( $.yote.is_logged_in() ) { to_logged_in( $.yote.get_login().get_handle() ) } else { to_login('need to log in')  }  } );
	if( $.yote.is_logged_in() ) {
            to_logged_in( $.yote.get_login().get_handle() );
	} else {
	    logout();
	}

    }, //make_login_box

    make_table:function() {
	return {
	    html:'<table>',
	    add_header_row : function( arry ) {
		this.html = this.html + '<tr>';
		for( var i=0; i<arry.length; i++ ) {
		    this.html = this.html + '<th>' + arry[i] + '</th>';
		}
		this.html = this.html + '</tr>';
		return this;
	    },
	    add_row : function( arry ) {
		this.html = this.html + '<tr>';
		for( var i=0; i<arry.length; i++ ) {
		    this.html = this.html + '<td>' + arry[i] + '</td>';
		}
		this.html = this.html + '</tr>';		
		return this;
	    },
	    add_param_row : function( arry ) {
		this.html = this.html + '<tr>';		
		if( arry.length > 0 ) {
		    this.html = this.html + '<th>' + arry[0] + '</th>';
		}
		for( var i=1; i<arry.length; i++ ) {
		    this.html = this.html + '<td>' + arry[i] + '</td>';
		}
		this.html = this.html + '</tr>';		
		return this;
	    },
	    get_html : function() { return this.html + '</table>'; }
	}
    }, //make_table

	
    button_actions:function( args ) {
	var but     = args[ 'button' ];
	var action  = args[ 'action' ];
	var texts   = args[ 'texts'  ] || [];
	var req_texts = args[ 'required' ];
	var exempt  = args[ 'cleanup_exempt' ] || {};

	check_ready = (function(rt,te) { return function() {
	    var t = rt || te;
	    for( var i=0; i<t.length; ++i ) {
		if( ! $( t[i] ).val().match( /\S/ ) ) {
	    	    $( but ).attr( 'disabled', 'disabled' );
		    return false;
		}
	    }
	    
	    $( but ).attr( 'disabled', false );
	    return true;
	} } )( req_texts, texts ) // check_ready

	for( var i=0; i<texts.length - 1; ++i ) {
	    $( texts[i] ).keyup( check_ready );
	    $( texts[i] ).keypress( (function(box) {
		return function( e ) {
		    if( e.which == 13 ) {
			$( box ).focus();
		    }
		} } )( texts[i+1] ) );
	}

	act = (function( c_r, a_f, txts ) { return function() {
	    if( c_r() ) {
		a_f();
		for( var i=0; i<txts.length; ++i ) {
		    if( ! exempt[ txts[i] ] ) {
			$( txts[i] ).val( '' );
		    }
		}
	    }
	} } ) ( check_ready, action, texts );

	$( texts[texts.length - 1] ).keyup( check_ready );
	$( texts[texts.length - 1] ).keypress( (function(a) { return function( e ) {
	    if( e.which == 13 ) {
		a();
	    } } } )(act) );

	$( but ).click( act );

	check_ready();

    } // button_actions

}//$.yote.util
