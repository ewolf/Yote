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
                o.stage(k,newval);
                if( initial != newval || o.is_dirty(k)) {
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

                if( initial != newval || o.is_dirty(k)) {
                    $(id).css('background-color','lightyellow' );
                } else {
                    $(id).css('background-color','white' );
                }

                if( as_list == true ) {
                    newval = newval.split( /\r\n|\r|\n/ );
                    for( var nk in newval ) {
                        o.stage( nk, newval[nk] );
                    }
                }
                else {
                    o.stage(k,newval);
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
                        if( 0 + newid > 0 ) {
                            o.stage(k,fetch_obj(newid,obj._app));
                        } else {
                            o.stage(k,undefined);
                        }
                        if( initial != newid || o.is_dirty(k) ) {
                            $(id).css('background-color','lightyellow' );
                        } else {
                            $(id).css('background-color','white' );
                        }
                    }
                } )(yote_obj,yote_fieldname,'#'+idname,current_id)
            );
        }
    }, //stage_select

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
	var target = args['target'];
	var logged_in_f = args['on_login']   || args['on_in'];
	var created_f = args['on_register']  || args['on_in'];
	var recover_f = args['on_recover']   || args['on_in'];
	var logged_out_f = args['on_logout'];

	$(target).empty();
	$(target).append( "<span id=login_msg_outerspan style=display:none><span id=login_msg_span class=warning></span><BR></span>" +

			  // do login
			  "<div style=display:none id=y_login_div>" +
			  "<table><tr><td>Handle</td><td><input class=login id=login type=text></td>" +
			  "</tr><tr><td>Password</td><td><input class=login id=password type=password>" +
			  "</td></tr></table><br>" +
			  "<input class=login id=login_submit type=submit value=Login>" +
			  " <a href='#' id=register_link>Register</a>" +
			  " <a href='#' id=forgot_link>Forgot</a>" +
			  "</div>" +

			  // not logged in
			  "<div style=display:none id=y_not_loggedin>" +
			  "Not logged in. <a href='#' id=login_link>Login</a> &nbsp;" +
			  "<a href='#' id=register_link>Register</a>" +
			  "</div>" +

			  // register account
			  "<div style=display:none id=y_register_account>" +
			  "<table><tr><td>Handle</td><td><input class=register id=login type=text></td>" +
			  "</tr><tr><td>Email</td><td><input class=register id=email type=text>" +
			  "</tr><tr><td>Password</td><td><input class=register id=password type=password>" +
			  "</td></tr></table>" + 
			  "<input id=register_submit type=submit value=Register> " +
			  "  <div id=register_login_link_div><a href='#' id=login_link>Login</a></div>" +
			  "</div>" +

			  // recover
			  "<div style=display:none id=y_recover_account>" +
			  "Email <input class=recover id=email> " +
			  "<input id=recover_submit type=submit value=Recover>" +
                          "<a href='#' id=login_link>Login</a>" + 
			  "</div>" +

			  // logged in
			  "<div style=display:none id=y_logged_in>" +
			  "Logged in as <span class=logged_in id=handle></span><BR> [<a id=logout_link href='#'>logout</a>]" +
			  "</div>"
			);
	var message = function( msg ) {
            if( typeof msg === 'string' ) {
	        $( target + ' #login_msg_span').empty()
	        $( target + ' #login_msg_span').append( msg )
	        $( target + ' #login_msg_outerspan').show()	    
	    } else {
	        $( target + ' #login_msg_span').empty()
	        $( target + ' #login_msg_outerspan').hide()
            }
	}
	var install_function = function( f ) { return function() { f(); } }
	var on_enter = function(f) { return function(e) { if(e.which == 13 ) { f(); } } }
	var to_login = function(msg) {
	    console.dir( msg );
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
	}
	var do_login = function() {
	    console.dir( $( target + ' .login#login' ) );
	    $.yote.login( $( target + " .login#login").val(), $(target + " .login#password").val(),
			  function(data) { //pass
			      console.dir( $.yote.login_obj )
			      
			      to_logged_in($.yote.login_obj.get('handle'));
			      // note the following line will work but is not closure safe yet.
			      if( typeof logged_in_f === 'function' ) { logged_in_f(); }
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
	    $.yote.root.recover_password( { e:$( target + ' .recover#email' ).val(), 
					    u:window.location.href,
					    t:window.location.href.replace(/[^\/]$/, 'reset.html' )
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

	//button actions
	$( target + ' #login_submit').click( install_function(do_login || nada) );
	$( target + ' .login#login,' + target + ' .login#password' ).keypress( on_enter(do_login) );
	$( target + ' #register_submit').click( install_function(do_register || nada) );
	$( target + ' .register#login,' + target + ' .register#password,' + target + ' .register#email' ).keypress( on_enter(do_register) );
	$( target + ' .recover#email' ).keypress( on_enter(do_recover) );
	$( target + ' #recover_submit' ).click( install_function(do_recover || nada) );

	if( $.yote.is_logged_in() ) {
            to_logged_in( $.yote.get_login().get_handle() );
	} else {
	    logout();
	}

    } //make_login_box

}//$.yote.util