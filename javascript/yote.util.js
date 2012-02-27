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
                console.dir(o);
                if( initial != newval ) {
                    $(id).css('background-color','lightyellow' );
                } else {
                    $(id).css('background-color','white' );
                }
            }
        } )(yoteobj,fieldname,'#'+idname,val) );
        return $( '#' + idname );
    }, //stage_text_field

    /*
      yote_obj/yote_fieldname 
          - object and field to set an example from the list
            list_fieldname - field in the list objects to get the item name for.
    */
    stage_select:function(attachpoint,yote_obj,yote_fieldname,list,list_fieldname) {},

    make_select:function(attachpoint,list,list_fieldname) {
	var idname = this.next_id();
        attachpoint.append( '<select id='+idname+'>' );
	for( var i in list ) {
	    var item = list[i];
	    $( '#'+idname ).append( '<option value='+item.id+'>'+item.get(list_fieldname)+'</option>' );
	}
	return $( '#' + idname );
    },
    make_login_box:function(args) {
	    var target = args['target'];
	    var logged_in_f = args['on_login'];
	    var logged_out_f = args['on_logout'];
	    var created_f = args['on_register'];
	    var recover_f = args['on_recover'];
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
			              "<input id=register_submit type=submit value=Register> <a href='#' id=login_link>Login</a>" +
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
	        $.yote.login( $( target + " .login#login").val(),
			              $(target + " .login#password").val(),
			              function(data) { //pass
			                  to_logged_in($.yote.acct.get('handle'));
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
	            $.yote.create_account( $( target + " .register#login").val(),
				                       $( target + " .register#password").val(),
				                       $( target + " .register#email").val(),
				                       function(data) { //pass
				                           to_logged_in($.yote.acct.get('handle'),"Created Account");
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
	        $.yote.recover_password( $( target + ' .recover#email' ).val(), 
                                     window.location.href,
                                     window.location.href.replace(/[^\/]$/, 'reset.html' ),
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
	        $( target + ' > div#y_not_loggedin' ).show();
	        $( target + ' #password' ).val('');
	        $.yote.logout();
	        if( typeof logged_out_f === 'function' ) { logged_out_f(); }
	    }
	    //link actions
	    $( target + ' #login_link').click( install_function(to_login) );
	    $( target + ' #register_link').click( install_function(to_register) );
	    $( target + ' #logout_link').click( install_function(logout) );
	    $( target + ' #forgot_link').click( install_function(to_recover) );

	    //button actions
	    $( target + ' #login_submit').click( install_function(do_login) );
	    $( target + ' .login#login,' + target + ' .login#password' ).keypress( on_enter(do_login) );
	    $( target + ' #register_submit').click( install_function(do_register) );
	    $( target + ' .register#login,' + target + ' .register#password,' + target + ' .register#email' ).keypress( on_enter(do_register) );
	    $( target + ' .recover#email' ).keypress( on_enter(do_recover) );
	    $( target + ' #recover_submit' ).click( install_function(do_recover) );

	    if( $.yote.is_logged_in() ) {
	        var acct = $.yote.get_account();
	        $( target + ' > .logged_in#handle' ).val( acct.get('handle') );
	        $( target + ' > div' ).hide();
	        $( target + ' > div#y_logged_in' ).show();
	    } else {
	        logout();
	    }

    } //make_login_box

}//$.yote.util