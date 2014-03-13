/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Version 0.027
 */
$.yote.util = {
    ids:0,

    url_params:function() {
	if( window.location.href.indexOf('?') == -1 ) {
	    return {};
	}
        var parts  = window.location.href.split('?');
        var params = parts[1].split('&');
        var ret = {};
        for( var i=0; i<params.length; ++i ) {
            var pair = params[i].split('=');
	    ret[ pair[0] ] = pair[1];
        }
	return ret;
    }, //url_params

    format_date: function( date, format ) {
	if( format ) {
	    var buf = '';
	    for( var i=0; i<format.length; i++) {
		var chara = format.charAt( i );
		if( chara == 'Y' ) buf += date.getUTCFullYear();
		else if( chara == 'M' ) buf += (1 + date.getUTCMonth()) > 9 ? 1 + date.getUTCMonth() : '0' + ( 1 + date.getUTCMonth() );
		else if( chara == 'D' ) buf += date.getUTCDate()    > 9 ? date.getUTCDate()    : '0' + date.getUTCDate();
		else if( chara == 's' ) buf += date.getUTCSeconds() > 9 ? date.getUTCSeconds() : '0' + date.getUTCSeconds();
		else if( chara == 'h' ) buf += date.getUTCHours()   > 9 ? date.getUTCHours()   : '0' + date.getUTCHours();
		else if( chara == 'm' ) buf += date.getUTCMinutes() > 9 ? date.getUTCMinutes() : '0' + date.getUTCMinutes();
		else buf += chara;
	    }
	    return buf;
	}
	return date.toUTCString();
    },

    registered_items : {},

    registered_templates : {},

    register_items:function( hashed_items ) {
	for( var key in hashed_items ) {
	    this.registered_items[ key ] = hashed_items[ key ];
	}
    },
    register_item:function( name, val ) {
	this.registered_items[ name ] = val;
    },
    register_template_variable:function( name, val ) {
	this.registered_items[ name ] = val;
    },
    button_actions:function( args ) {
	var cue = {};
	if( args[ 'cleanup_exempt' ] ) {
	    for( var i=0; i < args[ 'cleanup_exempt' ].length; i++ ) {
		cue[ args[ 'cleanup_exempt' ][ i ] ] = true;
	    }
	}
	var ba = {
	    but         : args[ 'button' ],
	    action      : args[ 'action' ] || function(){},
	    on_escape   : args[ 'on_escape' ] || function(){},
	    texts       : args[ 'texts'  ] || [],
	    t_values    : args[ 'texts' ].map( function(it,idx){ return $( it ).val(); } ),
	    req_texts   : args[ 'required' ],
	    req_indexes : args[ 'required_by_index' ],
	    req_fun     : args[ 'required_by_function' ],
	    exempt      : cue,
	    extra_check : args[ 'extra_check' ] || function() { return true; },

	    check_ready : function() {
		var me = this;
		var ecval = me.extra_check();
		var t = me.req_texts || me.texts;
		if( typeof me.req_fun === 'function' ) {
		    if( me.req_fun( me.texts ) != true ) {
			$( me.but ).attr( 'disabled', 'disabled' );
			return false;
		    }
		}
		else if( typeof me.req_indexes !== 'undefined' ) {
		    for( var i=0; i<me.req_indexes.length; ++i ) {
			if( $( me.texts[ me.req_indexes[ i ] ] ).val() == me.t_values[ i ] ) {
	    		    $( me.but ).attr( 'disabled', 'disabled' );
			    return false;
			}
		    }
		}
		else {
		    for( var i=0; i<t.length; ++i ) {
			if( $( t[ i ] ).val() == me.t_values[ i ] ) {
	    		    $( me.but ).attr( 'disabled', 'disabled' );
			    return false;
			}
		    }
		}
		$( me.but ).attr( 'disabled', ! ecval );
		return ecval;
	    }, //check_ready

	    init:function() {
		var me = this;
		for( var i=0; i<me.texts.length - 1; ++i ) {
		    if( $( me.texts[i] ).prop('type') == 'checkbox' ) {
			$( me.texts[i] ).click( function() { me.check_ready(); return true; } );
		    }
		    else {
			$( me.texts[i] ).keyup( function() { me.check_ready(); return true; } );
			$( me.texts[i] ).keypress( (function(box,oe) {
			    return function( e ) {
				if( e.which == 13 ) {
				    $( box ).focus();
				} else if( e.which == 27 ) {
				    oe();
				}
			    } } )( me.texts[i+1], me.on_escape ) );
		    }
		}
		$( me.texts[me.texts.length - 1] ).keyup( function() { me.check_ready(); return true; } );
		$( me.texts[me.texts.length - 1] ).keypress( function( e ) {
		    if( e.which == 13 ) {
			me.act();
		    } else if( e.which == 27 ) {
			me.on_escape();
		    }
		} );
		$( me.but ).click( function() { me.act() } );
		me.check_ready();
	    }, //init

	    act : function() {
		var me = this;
		if( me.check_ready() ) {
		    me.action();
		    for( var i=0; i<me.texts.length; ++i ) {
			if( ! me.exempt[ me.texts[i] ] ) {
			    $( me.texts[i] ).val( '' );
			}
		    }
		    me.t_values    = me.texts.map( function(it,idx){ return $( it ).val(); } );
		}
	    } //act
	} // ba

	ba.init();

	return ba;

    }, //button_actions

    next_id:function() {
        return 'yidx_'+this.ids++;
    },

    implement_edit:function( item, field, on_edit_function, id ) {
	var id_root  = id || item.id + '_' + field;

	var editor = {
	    item  : item,
	    field : field,
	    on_edit_function : on_edit_function,
	    div_id  : 'ed_'  + id_root,
	    txt_id  : 'txt_' + id_root,
	    canc_id : 'txc_' + id_root,
	    go_id   : 'txb_' + id_root,

	    go_normal : function() {
		$( '#' + this.div_id ).removeClass( 'edit_ready' );
		$( '#' + this.div_id ).off( 'click' );
	    }, //implement_edit.go_normal

	    stop_edit : function() {
		var me = editor;
		var val = item.get( field ) || '';
		// do filtering here
		//val = val.replace( /[\n\r]/g, '<BR>' );
		if( $( '#' + me.div_id ).attr( 'as_html' ) == 'true' ) {
		    $( '#' + me.div_id ).empty().append( val );
		} else {
		    $( '#' + me.div_id ).empty().text( val );
		}
		me.go_normal();
		$.yote.util.implement_edit( me.item, me.field, me.on_edit_function, id_root );
	    }, //implement_edit.stop_edit

	    apply_edit : function() {
		var me = editor;
		var val = $( '#' + me.txt_id ).val();
		me.item.set( me.field, val );
		if( me.on_edit_function )
		    me.on_edit_function(val,item,field);
		me.stop_edit();
	    }, //apply_edit

	    go_edit : function() {
		var me = editor;
		var rows = 2;
		var val = item.get( field ) || '';
		if( val != null ) {
		    rows = Math.round( val.length / 25 );
		}
		if( rows < 2 ) { rows = 2; }
		var w = $( '#' + me.div_id ).width() + 40;
		if( w < 100 ) w = 100;
		var h = $( '#' + me.div_id ).height() + 20;
		$( '#' + me.div_id ).empty().append( '<textarea STYLE="width:' + w + 'px;' +
						  'height:' + h + 'px;" class="in_edit_same" id="' + me.txt_id + '"></textarea><BR>' +
						  '<button class="cancel" type="button" id="' + me.canc_id + '">cancel</button> ' +
						  '<button class="go" type="button" id="' + me.go_id + '">Go</button> ' );
		$( '#' + me.txt_id ).val( val );
		$( '#' + me.txt_id ).keyup( function(e) {
		    if( item.get( field ) == $( '#' + me.txt_id ).val() ) {
			$( '#' + me.txt_id ).addClass( 'in_edit_same' );
			$( '#' + me.txt_id ).removeClass( 'in_edit_changed' );
		    } else {
			$( '#' + me.txt_id ).removeClass( 'in_edit_same' );
			$( '#' + me.txt_id ).addClass( 'in_edit_changed' );
		    }
		} );
		$( '#' + me.txt_id ).keypress( function(e) {
		    if( e.keyCode == 27 ) { //escape like cancel
			me.stop_edit();
		    }
		} );
		$( '#' + me.go_id ).click( me.apply_edit );
		$( '#' + me.canc_id ).click( me.stop_edit );
		$( '#' + me.txt_id ).focus();
		$( '#' + me.div_id ).off( 'click' );
		$( '#' + me.div_id ).off( 'mouseenter' );
		$( '#' + me.div_id ).off( 'mouseleave' );
	    }, //implement_edit.go_edit

	    show_edit : function() {
		var me = editor;
		if( $( '#' + me.canc_id ).length == 0 ) {
		    $( '#' + me.div_id ).addClass( 'edit_ready' );
		    $( '#' + me.div_id ).click( function() { me.go_edit() } );
		}
	    },

	    init : function() {
		var me = editor;
		$( '#' + me.div_id ).mouseleave( function() { me.go_normal() } ).mouseenter( function() { me.show_edit() } );
		var val = item.get( field ) || '';
		if( $( '#' + me.div_id ).attr( 'as_html' ) == 'true' ) {
		    $( '#' + me.div_id ).empty().append( val );
		} else {
		    $( '#' + me.div_id ).empty().text( val );
		}
	    }
	}; //editor
	editor.init();
	return editor;
    }, //implement_edit

    prep_edit:function( item, fld, extra, as_html, id ) {
	var extr = extra || [];
	var div_id   = id || item.id + '_' + fld;
	return '<DIV CLASS="input_div ' + extr.join(' ') + '" ' + ( as_html ? ' as_html="true" ' : '' ) + ' id="ed_' + div_id + '"></div>';
    }, //prep_edit

    make_table:function( classes ) {
	var xtr = classes ? 'class="' + classes.join( ' ' ) + '"' : '';
	return {
	    html:'<table ' + xtr + '>',
	    next_row_class:'even-row',
	    add_header_row : function( arry, row_classes, header_classes ) {
		row_classes = row_classes ? row_classes : [];
		row_classes.push( this.next_row_class );
		header_classes = header_classes ? header_classes : [];

		this.html = this.html + '<tr class="' + row_classes.join( ' ' ) + '">';
		if( this.next_row_class == 'even-row' ) {
		    this.next_row_class = 'odd-row';
		} else {
		    this.next_row_class = 'even-row';
		}

		var cls = 'even-col';
		for( var i=0; i<arry.length; i++ ) {
		    var colname = typeof arry[i] === 'function' ? arry[i]() : arry[i];
		    this.html = this.html + '<th class="' + cls + ' ' + header_classes.join( ' ' ) + '">' + colname + '</th>';
		    if( cls == 'even-col' ) {
			cls = 'odd-col';
		    } else {
			cls = 'even-col';
		    }
		}
		this.html = this.html + '</tr>';
		return this;
	    },
	    add_row : function( arry, row_classes, cell_classes ) {
		row_classes = row_classes ? row_classes : [];
		cell_classes = cell_classes ? cell_classes : [];

		this.html = this.html + '<tr class="' + this.next_row_class + ' ' + row_classes.join( ' ' ) + '">';
		if( this.next_row_class == 'even-row' ) {
		    this.next_row_class = 'odd-row';
		} else {
		    this.next_row_class = 'even-row';
		}

		var cls = 'even-col';
		for( var i=0; i<arry.length; i++ ) {
		    this.html = this.html + '<td class="' + cls + ' ' + cell_classes.join( ' ' ) + '">' + arry[i] + '</td>';
		    if( cls == 'even-col' ) {
			cls = 'odd-col';
		    } else {
			cls = 'even-col';
		    }
		}
		this.html = this.html + '</tr>';
		return this;
	    },
	    add_param_row : function( arry, row_classes, header_classes, cell_classes ) {
		row_classes = row_classes ? row_classes : [];
		cell_classes = cell_classes ? cell_classes : [];

		this.html = this.html + '<tr class="' + this.next_row_class + ' ' + row_classes.join(' ') +  '">';
		if( this.next_row_class == 'even-row' ) {
		    this.next_row_class = 'odd-row';
		} else {
		    this.next_row_class = 'even-row';
		}
		if( arry.length > 0 ) {
		    this.html = this.html + '<th class="even-col ' + header_classes.join(' ') + '">' + arry[0] + '</th>';
		}
		var cls = 'odd-col';
		for( var i=1; i<arry.length; i++ ) {
		    this.html = this.html + '<td class="' + cls + ' ' + cell_classes.join( ' ' ) + '">' +  arry[i] + '</td>';
		    if( cls == 'even-col' ) {
			cls = 'odd-col';
		    } else {
			cls = 'even-col';
		    }
		}
		this.html = this.html + '</tr>';
		return this;
	    },
	    get_html : function() { return this.html + '</table>'; }
	}
    }, //make_table

    login_control:function( args ) {
	var lc = {
	    attachpoint      : args[ 'attachpoint' ],
	    msg_function     : args[ 'msg_function' ]              || function(m,c){ c ? $( '#login_msg' ).removeClass().addClass( c ) : '';$( '#login_msg' ).empty().append( m ); },
	    log_in_status    : args[ 'log_in_status_attachpoint' ] || '#logged_in_status',
	    after_login_fun  : args[ 'after_login_function' ],
	    after_logout_fun : args[ 'after_logout_function' ],
	    access_test      : args[ 'access_test' ] || function() { return $.yote.is_logged_in(); },
	    logged_in_fail_msg : args[ 'logged_in_fail_msg' ],
	    app                : args[ 'app' ] || $.yote.fetch_root(),

	    on_login:function() {
		var thislc = this;
		$( thislc.attachpoint ).empty();
		$( thislc.log_in_status ).empty().append(
		    'Logged in as ' + $.yote.get_login().get_handle() + '<BR><A href="#" id="logout">Log Out</A>'
		);
		$( '#logout' ).click( function() {
		    thislc.msg_function( 'logged out' );
		    $( thislc.log_in_status ).empty();

		    if( typeof thislc.on_logout_fun === 'function' ) {
			thislc.on_logout_fun();
		    }
		    $.yote.logout();
		    if( typeof thislc.after_logout_fun === 'function' )
			thislc.after_logout_fun();
		} );
	    }, //on_login

	    make_recovery:function() {
		var thislc = this;
		thislc.msg_function('');
		$( thislc.attachpoint ).empty().append(
		    '<div class="panel core" id="recover_acct_div">' +
			'<DIV id="recover_acct_msg"></DIV>' +
			'<P>' +
			'<input type="email" placeholder="Email (optional)" id="em" size="8">' +
			'<A id="recover_acct_b" class="hotlink" href="#">Recover</A> <A HREF="#" id="cancel_b">[X]</A>' +
			'</div>'
		);
		$( '#em' ).focus();
		$( '#cancel_b' ).click( function() {
		    thislc.msg_function('');
		    thislc.needs_login();
		} );

		$.yote.util.button_actions( {
		    button : '#recover_acct_b',
		    texts  : [ '#em' ],
		    action : function() {
			thislc.app.recover_password(
			    $( '#em' ).val(),
			    function( msg ) {
				thislc.msg_function( msg );
			    },
			    function( err ) {
				thislc.msg_function( err, 'error' );
			    } );
		    } //action
		} );
	    }, //make_recovery

	    make_create_login:function() {
		var thislc = this;
		thislc.msg_function('');
		$( thislc.attachpoint ).empty().append(
		    '<div class="panel core" id="create_acct_div">' +
			'<DIV id="login_msg"></DIV>' +
			'<P><input type="text" id="username" placeholder="Name" size="6">' +
			'<input type="email" placeholder="Email (optional)" id="em" size="8">' +
			'<input type="password" placeholder="Password" id="pw" size="6">' +
			'<A id="create_account_b" class="hotlink" href="#">Create</A> <A HREF="#" id="cancel_b">[X]</A>' +
			'</div>'
		);
		$( '#username' ).focus();
		$( '#cancel_b' ).click( function() {
		    thislc.msg_function('');
		    thislc.needs_login();
		} );

		$.yote.util.button_actions( {
		    button : '#create_account_b',
		    texts  : [ '#username', '#em', '#pw' ],
		    required : [ '#username', '#pw' ],
		    action : function() {
			var login = thislc.app.create_login(
			    {
				h : $( '#username' ).val(),
				p : $( '#pw' ).val(),
				e : $( '#em' ).val() },
			    function( msg ) {
				if( thislc.access_test( $.yote.fetch_account() ) ) {
				    thislc.msg_function( msg );
				    if( typeof thislc.on_login_fun === 'function' )
					thislc.on_login_fun();
				    if( typeof thislc.after_login_fun === 'function' )
					thislc.after_login_fun();
				} else if( thislc.logged_in_fail_msg ) {
				    thislc.msg_function( thislc.logged_in_fail_msg, 'error' );
				    $.yote.logout();
				}
			    },
			    function( err ) {
				thislc.msg_function( err, 'error' );
			    }  );
		    } //action
		} );
	    }, //make_create_login

	    needs_login:function() {
		var thislc = this;
		$( thislc.attachpoint ).empty().append(
		    '<A class="hotlink big" HREF="#" id="go_to_login_b">Log In</A> <BR>' +
		    '<A class="hotlink small" HREF="#" id="create_account_b">Create an Account</A>'
		);
		$( '#go_to_login_b' ).click( function() { thislc.make_login() } );
		$( '#create_account_b' ).click( function() { thislc.make_create_login() } );
	    }, //needs_login

	    make_login:function() {
		var thislc = this;
		$( thislc.attachpoint ).empty().append(
		    '<div class="panel core" id="create_acct_div">' +
			'<DIV id="login_msg"></DIV>' +
			'Log In' +
			'<input type="text" id="username" placeholder="Name" size="6">' +
			'<input type="password" placeholder="Password" id="pw" size="6"> <BUTTON type="BUTTON" id="log_in_b">Log In</BUTTON> <A id="cancel_b" href="#">[X]</A></P> ' +
			'<A id="reset_password_b" class="hotlink" href="#">Forgot Password</A><BR>' +
			'<A id="create_account_b" class="hotlink" href="#">Create an Account</A> ' +
			'</div>'
		);
		$( '#username' ).focus();

		$( '#cancel_b' ).click( function() {
		    thislc.msg_function( '' );
		    thislc.needs_login();
		} );

		$.yote.util.button_actions( {
		    button :  '#log_in_b',
		    texts  : [ '#username', '#pw' ],
		    action : function() {
			thislc.msg_function('');
			$.yote.login( $( '#username' ).val(),
				      $( '#pw' ).val(),
				      function( msg ) {
					  if( thislc.access_test( $.yote.fetch_account() ) ) {
					      if( typeof thislc.on_login_fun === 'function' )
						  thislc.on_login_fun();
					      if( typeof thislc.after_login_fun === 'function' )
						  thislc.after_login_fun();
					  } else if( thislc.logged_in_fail_msg ) {
					      thislc.msg_function( thislc.logged_in_fail_msg, 'error' );
					      $.yote.logout();
					  }
				      },
				      function( err ) {
					  thislc.msg_function( err, 'error' );
				      } );
		    }
		} );

		$( '#reset_password_b' ).click( function() { thislc.make_recovery(); } );
		$( '#create_account_b' ).click( function() { thislc.make_create_login(); } );
	    } //make_login
	};
	if( ! lc.access_test( $.yote.fetch_account() ) ) {
	    lc.make_login();
	}

	lc.on_logout_fun = args[ 'on_logout_function' ] || lc.make_login;
	lc.on_login_fun = args[ 'on_login_fun' ]  || lc.on_login;
	if( lc.access_test( $.yote.fetch_account() ) ) {
	    if( typeof lc.on_login_fun === 'function' )
		lc.on_login_fun();
	    if( typeof lc.after_login_fun === 'function' )
		lc.after_login_fun();
	} else {
	    if( lc.logged_in_fail_msg ) {
		lc.msg_function( lc.logged_in_fail_msg, 'error' );
		$.yote.logout();
	    }
	    if( typeof lc.on_logout_fun === 'function' )
		lc.on_logout_fun();
	    if( typeof lc.after_logout_fun === 'function' )
		lc.after_logout_fun();
	}

	return lc;
    }, //login_control

    check_edit:function( fld, updated_fun, extra_classes ) {
	var div_id = '__' + $.yote.util.next_id();
	return function( item, is_prep ) {
	    if( is_prep ) {
		extra_classes = extra_classes ? extra_classes : [];
		return '<input type="checkbox" id="' + div_id + '" ' +
		    ( 1 * item.get( fld ) == 1 ? ' checked' : '' ) +
		    ' class="' + extra_classes.join(' ') + '">';
	    } else {
		$( '#' + div_id ).click( function() {
		    var chked = $( '#' + div_id ).is( ':checked' );
		    item.set( fld, chked ? 1 : 0 );
		    updated_fun( chked, item, fld );
		} );
	    }
	};
    }, //check_edit

    // makes a select that controls a field on an object that is also an object.
    select_obj_edit:function( fld, list_obj, list_item_field, after_change_fun ) {
	var div_id = '__' + $.yote.util.next_id();
	return function( item, is_prep ) {
	    if( is_prep ) {
		return '<SELECT id="' + div_id + '">' + list_obj.to_list().map(function(it,idx){if( typeof it !== 'object' ) return '<option value="' + it + '">' + it + '</option>'; return '<option ' + ( item.get(fld) && item.get(fld).id == it.id ? 'SELECTED ' : '' ) + ' value="'+idx+'">'+it.get(list_item_field)+'</option>'}).join('') + '</SELECT>';
	    }
	    else {
		$( '#' + div_id ).change( function() {
		    item.set( fld, list_obj.get( $(this).val() * 1 ) );
		    if( after_change_fun ) after_change_fun(item,list_obj);
		} );
	    }
	};
    }, //select_obj_edit

    // makes a select that controls a text field on an object
    select_edit:function( fld, list_obj, after_change_fun ) {
	var div_id = '__' + $.yote.util.next_id();
	return function( item, is_prep ) {
	    if( is_prep ) {
		return '<SELECT id="' + div_id + '">' + list_obj.map(function(it,idx){return '<option ' + ( item.get(fld) && item.get(fld) == it ? 'SELECTED ' : '' ) + ' value="'+idx+'">'+it+'</option>'}).join('') + '</SELECT>';
	    }
	    else {
		$( '#' + div_id ).change( function() {
		    item.set( fld, list_obj[ $(this).val() * 1 ] );
		    if( after_change_fun ) after_change_fun(item);
		} );
	    }
	};
    }, //select_edit

    // a template is a server side template here, meaning it has interpolted text
    template_edit:function( template_name, extra_classes, on_edit_f ) {
	var id = '__' + $.yote.util.next_id();
	return function( item, is_prep ) {
	    var tmplt = item.get( template_name );
	    if( ! tmplt ) {
		tmplt = $.yote.fetch_root().new_template();
	    }
	    if( is_prep ) {
		return $.yote.util.prep_edit( tmplt, 'text', extra_classes, false, id );
	    } else {
		$.yote.util.implement_edit( tmplt, 'text', on_edit_f, id );
	    }
	};
    }, //template_edit

    col_edit:function( fld, extra_classes, on_edit_f ) {
	var id = '__' + $.yote.util.next_id();
	return function( item, is_prep ) {
	    if( is_prep ) {
		return $.yote.util.prep_edit( item, fld, extra_classes, false, id );
	    } else {
		$.yote.util.implement_edit( item, fld, on_edit_f, id );
	    }
	};
    }, //col_edit

    cols_edit:function( flds, titles, extra_classes ) {
	var use_titles = titles || flds;
	var ids = [];
	for( var i=0; i<flds.length; i++ ) {
	    ids.push( '__' + $.yote.util.next_id() );
	}
	return function( item, is_prep ) {
	    if( is_prep ) {
		var tab = $.yote.util.make_table();
		for( var i=0; i<flds.length; i++ ) {
		    tab.add_param_row( [ use_titles[ i ], $.yote.util.prep_edit( item, flds[i], extra_classes, ids[ i ] ) ] );
		}
		return tab.get_html();
	    } else {
		for( var i=0; i<flds.length; i++ ) {
		    $.yote.util.implement_edit( item, flds[i], undef, ids[ i ] );
		}
	    }
	};
    }, //cols_edit

    reset_els:function(els) {
	for( var i in  els ) {
	    $( els[ i ] ).each(  function() {
		$( this ).attr( 'has_init', 'false' );
	    } );
	}
    }, //reset_els

    init_el:function(el) {
	var ct_id = el.attr( 'id' );
	var item = el.attr( 'item' );
	var args = { attachpoint : '#' + ct_id };
	if( el.attr( 'requires_root' ) == 'true' && ! $.yote.is_root() ) {
	    el.empty();
	    return;
	}
	var fields = [
	    'yote_button', 'yote_action_link',
	    'edit_requires','field','no_edit','after_edit_function','use_checkbox', 'use_select','use_select_obj','show','new_addto_function','action',
	    'container_name', 'paginate_type', 'paginate_order', 'is_admin','sel_list','list_field','list_obj',
	    'plimit','paginate_override',
	    'suppress_table', 'title', 'description', 'prefix_classname',
	    'include_remove', 'remove_button_text', 'remove_column_text',

	    'value','bare','checked',

	    'new_attachpoint',
	    'new_button', 'new_title', 'new_description',

	    'column_headers', 'column_placeholders', 'columns', 'new_columns', 'new_columns_required',
	    'new_required_by_index', 'new_column_titles', 'new_column_placeholders',
	    'new_requires', 'new_object_type',

	    'item', 'parent', 'show_count',
	    'after_load', 'after_render', 'show_when_empty','remove_function',
	    'new_required_by_function', 'new_function', 'after_new_function',

	    'control_table_name'
	];
	var attr, i, fld;
	for( i in fields ) {
	    fld = fields[i];
	    attr_val = el.attr( fld );
	    if( typeof attr_val == 'string' ) {
		// json
		if( attr_val.charAt(0) == '[' || attr_val.charAt(0) == '{' ) {
		    try {
			args[ fld ] = eval( attr_val );
		    } catch(err) {
			console.log( [ "ERR IN EVAL", err, attr_val ] );
			throw err;
		    }
		}
		// function
		else if( attr_val.charAt(0) == '*' ) {
		    var fs = attr_val.substring(1);
		    try {
			var f = eval( '['+fs+']' );
		    } catch(err) {
			console.log( [ "ERR IN EVAL", err, attr_val ] );
			throw err;
		    }
		    args[ fld ] = f[0];
		}

		// return values of function
		else if( attr_val.charAt(0) == '!' ) {
		    var fs = attr_val.substring(1);
		    try {
			var f = eval( '['+fs+']' );
		    } catch(err) {
			console.log( [ "ERR IN EVAL", err, attr_val ] );
			throw err;
		    }
		    args[ fld ] = f[0]();
		}

		// reference
		else if( attr_val.charAt(0) == '$' ) {
		    if( attr_val.charAt(1) == '$' )
			args[ fld ] = $.yote.get_by_id( attr_val.substring(2) );
		    else
			args[ fld ] = $.yote.util.registered_items[ attr_val.substring(1) ];
		}

		else {
		    args[ fld ] = attr_val;
		}
	    } //if a string
	} //each field

	if( el.hasClass( 'control_table' ) ) {
	    if( args[ 'item' ] ) {
		var ct = $.yote.util.control_table( args );
		if( args[ 'control_table_name' ] ) {
		    window[ args[ 'control_table_name' ] ] = ct;
		}
	    }
	    else {
		$( args[ 'attachpoint' ] ).empty();
	    }
	}
	else if( el.hasClass( 'yote_panel' ) ) {
	    if( args[ 'item' ] || args['show'] ) {
		$.yote.util.yote_panel( args );
	    }
	    else {
		$( args[ 'attachpoint' ] ).empty();
	    }
	} //yote_panel
	else if( el.hasClass( 'yote_button' ) ) {
	    if( args[ 'action' ] ) {
		$( args[ 'attachpoint' ] ).click(function(){
		    if( $.yote.util.functions[ args[ 'action' ] ] ) {
			$.yote.util.functions[ args[ 'action' ] ]( args[ 'item' ], args[ 'parent' ] );
		    } else {
			console.log( "'" + args['action'] + "' not found for button." );
		    }
		} );
	    } else {
		console.log( "No action found for button." );
	    }
	} //yote_button
	else if( el.hasClass( 'yote_action_link' ) ) {
	    if( args[ 'action' ] ) {
		$( args[ 'attachpoint' ] ).click(function(ev){
		    ev.preventDefault();
		    if( $.yote.util.functions[ args[ 'action' ] ] ) {
			$.yote.util.functions[ args[ 'action' ] ]( args[ 'item' ], args[ 'parent' ] );
		    } else {
			console.log( "'" + args['action'] + "' not found for button." );
		    }
		} );
	    } else {
		console.log( "No action found for button." );
	    }
	} //yote_action_link
	return;
    }, //init_el

    refresh_ui:function(sel) {
	$( sel || '.control_table,.yote_panel,.yote_button' ).each( function() {
	    $( this ).attr( 'has_init', 'false' );
	} );
	$.yote.util.init_ui();
    }, //refresh_ui

    init_ui:function() {
	var may_need_init = false;
	
	// REGISTER templates
	$( '.yote_template_definition' ).each( function() {
	    $.yote.util.register_template( $( this ).attr( 'template_name' ), $( this ).text() );
	} );

	// ACTIVATE templates
	$( '.yote_template' ).each( function() {
	    var el = $( this );
	    if( el.attr( 'has_init' ) == 'true' || el.attr( 'disabled' ) == 'true' ) {
		return;
	    }
	    el.attr( 'has_init', 'true' );
 	    var def_var    = $.yote.util._template_var( $( this ).attr( 'default_variable' ) );
	    var parent_var = el.attr( 'default_parent' );
	    var templ_name = el.attr( 'template' );
	    el.empty().append( $.yote.util.fill_template( templ_name, def_var, parent_var ) );	    
	} );
	
	$( '.control_table,.yote_panel,.yote_button,.yote_action_link' ).each( function() {
	    var el = $( this );
	    // init can be called multiple times, but only
	    // inits on the first time
	    if( el.attr( 'has_init' ) == 'true' || el.attr( 'disabled' ) == 'true' ) {
		return;
	    }
	    if( ! el.attr( 'id' ) ) {
		el.attr( 'id', '__CNTROL_ID_' + $.yote.util.next_id() );
	    }
	    el.attr( 'has_init', 'true' );
	    $.yote.util.init_el(el);
	    may_need_init = true;
	} ); //each div

	// run this to make sure no new control tables were created
	// as part of the next round
	if( may_need_init ) {
	    $.yote.util.init_ui();
	}
    }, //init_ui

    yote_panel:function( args ) {
	var item = args[ 'item' ];
	var field = args[ 'field' ];
	var show = args[ 'show' ];
	var after_show = args[ 'after_show' ];
	var bare = args[ 'bare' ]; //bare has no item and field normally
	if( show ) {
	    try {
		var f = eval( '[function(){' + ( show.indexOf('return') == -1 ? 'return ' + show : show ) + '}]' );
	    } catch(err) {
		console.log( [ "ERR IN YOTEPANEL EVAL",err, show ] );
		throw err;
	    }
	    try {
		var val = f[0]();
		$( args[ 'attachpoint' ] ).empty().append( f[0]() );
		if( after_show ) {
		    try {
			var f = eval( '[function(){' + after_show + '}]' );
		    } catch(err) {
			console.log( [ "ERR IN YOTEPANEL EVAL after_show",err, after_show ] );
			throw err;
		    }
		    f[0]();
		}
	    } catch(err) {
		console.log( [ "ERR IN YOTEPANEL function",err, show, f ] );
	    }
	}
	else if( field ) {
	    var use_html = false;
	    if( field.charAt(0) == '#' ) {
		use_html = true;
		field = field.substring(1);
	    }
	    if( ! args[ 'no_edit' ] && (  ! args[ 'edit_requires' ] ||
		  args[ 'edit_requires' ] == 'none'  ||
		( args[ 'edit_requires' ] == 'root'  && $.yote.is_root() ) ||
		( args[ 'edit_requires' ] == 'login' && $.yote.is_logged_in() ) ) ) {
		var aef = args[ 'after_edit_function' ];
		if( args[ 'use_checkbox' ] ) {
		    var ce_fun = $.yote.util.check_edit( field, aef );
		    $( args[ 'attachpoint' ] ).empty().append(
			ce_fun( item, true )
		    );
		    ce_fun( item, false );
		}
		else if( args[ 'use_select' ] ) {
		    var sel_fun = $.yote.util.select_edit( field, args[ 'sel_list' ], aef );
		    $( args[ 'attachpoint' ] ).empty().append(
			sel_fun( item, true )
		    );
		    sel_fun( item, false );
		}
		else if( args[ 'use_select_obj' ] ) {
		    var sel_fun = $.yote.util.select_obj_edit( field, args[ 'list_obj' ], args[ 'list_field' ], aef );
		    $( args[ 'attachpoint' ] ).empty().append(
			sel_fun( item, true )
		    );
		    sel_fun( item, false );
		}
		else {
		    var id = '__' + $.yote.util.next_id();
		    $( args[ 'attachpoint' ] ).empty().append(
			$.yote.util.prep_edit( item, field, '', use_html, id )
		    );
		    $.yote.util.implement_edit( item, field, aef, id );
		}
	    }
	    else {
		if( use_html ) {
		    $( args[ 'attachpoint' ] ).empty().append( item.get( field ) || '' );
		}
		else {
		    $( args[ 'attachpoint' ] ).text( item.get( field ) || '' );
		}
	    }
	} //if field
	else if( bare ) {
	    if( args[ 'use_checkbox' ] ) {
		var div_id = '__' + $.yote.util.next_id();
		$( args[ 'attachpoint' ] ).empty().append(
		    '<input type="checkbox" id="' + div_id + '" ' + ( args[ 'checked' ] ? 'checked' : '' ) + '>'
		);
		var f = $.yote.util.functions[ args[ 'after_edit_function' ] ];
		if( f ) {
		    $( '#' + div_id ).click( function() {
			var chked = $( '#' + div_id ).is( ':checked' );
			f( chked, args[ 'item' ], args[ 'parent' ], args[ 'template_id' ], args[ 'hash_key_or_index' ] );
		    } );
		}
	    }
	}
    }, //yote_panel

    make_list_paginator:function( lst_obj ) {
	return function( args ) {
	    var limit   = args[ 'limit' ];
	    var skip    = args[ 'skip' ];
	    var reverse = args[ 'reverse' ];
	    var ret = [];
	    var lst = lst_obj.to_list();
	    if( reverse ) {
		lst.reverse();
	    }
	    var max = lst.length < ( skip + limit ) ? lst.length : ( skip + limit );
	    for( var idx=skip; idx < max; idx++ ) {
		ret[ ret.length ] = lst[ idx ];
	    }
	    if( reverse ) {
		lst.reverse();
	    }
	    return {
		length:function() { return ret.length },
		get:function(i) { return ret[i]; }
	    };
	};
    }, //make_list_paginator

    // this tool is to create a table where the rows correspond to a list in a target
    // objects and the end user can add or remove the rows, or manipulate them
    control_table:function( args ) {
	var ct = {
	    ct_id		: this.next_id(),                         // a unique ID to make sure the namespace here is unique
	    search_terms	: args[ 'search_terms'] || [],                                     // used by search to keep track if search should be invoked or not

	    /* PAGINATION */
	    start		: 0,                                      // pagination start
	    plimit		: args[ 'plimit' ],                       // pagination limit
	    show_count          : typeof args[ 'show_count' ] === 'undefined' ? true : args[ 'show_count' ] && args[ 'show_count' ] != 'false',

	    search_fun		: args[ 'search_function' ],              // optional alternate search function. Uses the default. which is search_list
	    search_on		: args[ 'search_on' ],                    // List of what search fields to use for the item. This may or may not be used by the item's search function depending on how it is defined. If this is included, search will be activated.
	    display_search_box  : args[ 'display_search_box' ] || false,

	    /* DATA */
	    item		: args[ 'item' ],                          // item that contains the list
	    container_name      : args[ 'container_name' ],                     //   name of list attached to item
	    paginate_type	: args[ 'paginate_type' ] || 'list',       //   list or hash
	    paginate_order	: args[ 'paginate_order' ] || 'forward',   //   forward or backwards
	    paginate_override   : args[ 'paginate_override' ],
	    _paginate_override_fun : null,
	    is_admin            : args[ 'is_admin' ] || false,

	    /* HTML */
	    attachpoint		: args[ 'attachpoint' ],                   // selector that this control table will empty then fill with itself
	    column_headers	: args[ 'column_headers' ],                // list of column names to use. Not used if table is suppressed
	    suppress_table	: args[ 'suppress_table' ] || false,       // if true, the cells will not be formatted into a table
	    title		: args[ 'title' ],                         // Title text for this widget. If it is defined, it is put in a span with <prefix_classname>_title class
	    description		: args[ 'description' ],                   // Description text for this widget. If it is defined, it is put in a span with <prefix_classname>_description class
	    columns		: args[ 'columns' ],                       // A list of either strings or objects. If strings, an editible text field appears for the corresponding field of the row's object.
                                                                           // if object, then the following must be defined in the object :
                                                                           //     field - string to identify this cell. must be unique for this control table. Used to make a unique identifier string.
                                                                           //     render - function that takes the item as an argument and returns html for the cell
                                                                           //     after_render - called after the cell is rendered

	    /* STYLE */
	    prefix_classname    : args[ 'prefix_classname' ],              // Each element, like table, row, header, description gets its own class.
	                                                                   // If prefix_classname is foo, the table would get the 'foo_table' class.
	        /* classes : ( each of these will be there, as well as classes with prefix_classname replacing _ct.
                               For example, if prefix_classname="foo", there would be a foo_title and a _ct_title class )
                      _ct_title _ct_description _ct_search_div _ct_table _ct_new_title _ct_new_description _ct_new_item_table
		      _ct_new_item_row _ct_new_item_cell _ct_new_item_field _ct_new_item_btn _ct_row _ct_cell _ct_header _ct_delete_btn
		      _ct_to_start_btn _ct_back_btn _ct_forward_btn _ct_to_end_btn
		*/

	    /* ACTIONS */
	    after_load          : args[ 'after_load' ],                                   // this function is run once the first time the table is loaded.
	    after_render	: args[ 'after_render' ]   || function(list_of_items) {}, // run this function after rendering. It takes a single argument : list_of_items
	    show_when_empty     : args[ 'show_when_empty' ],                              // run this function if there were no items found for pagination. Function shold
	                                                                                  // return html that goes _IN PLACE_ of the table. Expects search item list as single parameter and passes the list of search terms as the single argument.
	    after_render_when_empty : args[ 'after_render_when_empty' ],                  // run this function if there were no items found for pagination. Function shold



	                                                                                  // expects search item list as single parameter. This is run after after_render, if it is run.
	    new_attachpoint	: args[ 'new_attachpoint' ],                              // selector for where to place new things
	    new_columns		: args[ 'new_columns' ],                                  // A list of objects or strings that is used to build the input for new objects.
	    new_columns_required     : args[ 'new_columns_required' ], //defaults to new_columns.
	    new_required_by_index    : args[ 'new_required_by_index' ],
	    new_object_type          : args[ 'new_object_type' ] || 'obj',
	    new_required_by_function : args[ 'new_required_by_function' ],
	    new_requires             : args[ 'new_requires' ] || 'login',
                                                                                          //  if strings, it creates a text input that is used to populate that field in the new object
	                                                                                  //  if :nodsIan object, it expect the following fields :
	                                                                                  //     field - a string that may be anything as long as it is unique to this particular call to control_table
	                                                                                  //     render - a function that takes an id as an argument and returns html
	                                                                                  //     after_render - a function called after the html is in the dom. Takes id as an argument
	                                                                                  //     on_create - a function called after the item has been created. Takes the new item and the control id as arguments.
	    new_column_titles	: args[ 'new_column_titles' ] || [],                            // Titles for the data fields
	    new_column_placeholders: args[ 'new_column_placeholders' ] || [],                       // Placeholder values for new data fields
	    new_function	: args[ 'new_function' ],                                 // function that return a new item for this pagination. Takes a hash ref of preoperties
	    new_addto_function	: args[ 'new_addto_function' ],                                 // function that return a new item for this pagination. Takes a hash ref of preoperties
	    after_new_fun	: args[ 'after_new_function' ],                           // function this is run after new_function and takes a as arguments : the newly created thing and a hash of key value pairs that were set for it.
	    new_button		: args[ 'new_button' ] || 'New',                          // text that appears on the create new item button. Default is 'New'
	    new_title		: args[ 'new_title' ],                                    // title for the new items widget that appears on top of it. If it is defined, it is put in a span with <prefix_classname>_new_title class
	    new_description	: args[ 'new_description' ],                              // description for new items for the widget that appears under the title. If it is defined, it is put in a span with <prefix_classname>_new_description class

	    include_remove      : args[ 'include_remove' ],   // If true, one more column will be created for the row : delete
	    remove_fun		: args[ 'remove_function' ],  // optional function to remove an item from this list. Takes the item and the item index (or key) as arguments.
	    remove_btn_txt	: args[ 'remove_button_text' ] || 'Delete', // Text that goes on the remove button. Default is 'Delete'.
	    remove_column_txt	: args[ 'remove_column_text' ] || 'Delete', // Text that goes on the remove column header. Default is 'Delete'.

	    _classes : function( cls ) {
		if( this.prefix_classname ) {
		    return this.prefix_classname + '_' + cls + ' ' + '_ct_' + cls;
		} else {
		    return '_ct_' + cls;
		}
	    },
	    _classes_array : function( cls ) {
		if( this.prefix_classname ) {
		    return [ this.prefix_classname + '_' + cls, '_ct_' + cls ];
		} else {
		    return [ '_ct_' + cls ];
		}
	    },
	    clear_search : function() {
		this.search_terms = [];
		this.refresh();
	    },

	    refresh : function() {
		var me = this;

		var paginate_function;

		(function(it) {
		    if( it.search_on && it.search_terms.length > 0 ) {
			paginate_function = function() {
			    if( it.search_fun ) {
				// TODO : make these into an argument list
				return it.search_fun( [ it.container_name, it.search_on, it.search_terms, it.plimit + 1, it.start ] );
			    } else {
				return it.item.paginate( { name : it.container_name, limit : it.plimit + 1, skip : it.start,
							   search_fields : it.search_on, search_terms : it.search_terms,
							   return_hash : it.paginate_type != 'list' ? 1 : 0,
							   reverse : it.paginate_order != 'forward' ? 1 : 0 } );
			    }
			}
		    }
		    else if( it.paginate_override ) {
			if( ! it._paginate_override_fun ) {
			    it._paginate_override_fun = $.yote.util.make_list_paginator( it.item.get( it.container_name ) );
			}
			paginate_function = function() { return it._paginate_override_fun( { limit : 1*it.plimit + 1, skip : it.start, reverse : it.paginate_order != 'forward' ? 1 : 0 } ) };
		    }
		    else {
			paginate_function = function() {
			    return it.item.paginate( { name : it.container_name, limit : 1*it.plimit + 1, return_hash : it.paginate_type != 'list' ? 1 : 0, skip : it.start, reverse : it.paginate_order != 'forward' ? 1 : 0 } );
			}
		    }
		} )( me );


		// calculated
		var count          = me.paginate_override ? me.item.get(me.container_name).length() : me.item.count( me.container_name ) * 1;
		me.plimit          = me.plimit ? me.plimit : count;
		var buf = me.title ? '<span class="' + me._classes( '_title' ) + '">' + me.title + '</span>' : '';
		buf    += me.description ? '<span class="' + me._classes( '_description' ) + '">' + me.description + '</span>' : '';

		if( me.dipslay_search_box ) {
		    buf += '<div id="_search_div_' + me.ct_id + '" class="' + me._classes( '_search_div' ) + '">Search <input class="' + me._classes( '_search_input' ) + '"  type="text" id="_search_txt_' + me.ct_id + '" value="' + me.search_terms.join(' ') + '"> ' +
			'<button type="button" id="_search_btn_' + me.ct_id + '">Search</button>' +
			'</div>';

		    if( me.terms.length > 0 ) {
			buf += 'Search Results : <BR>';
		    }
		}

		if( ! me.suppress_table ) {
		    var tab = $.yote.util.make_table( me._classes_array( 'table' ) );
		}


		if( me.new_attachpoint ) {
		    if( me.new_requires == 'none' ||
			( me.new_requires == 'root'  && $.yote.is_root() ) ||
			( me.new_requires == 'login' && $.yote.is_logged_in() ) ) {
			var bf = me.new_title ? '<div class="' + me._classes( '_new_title' ) + '">' + me.new_title + '</div>' : '';
			bf    += me.new_description ? '<div class="' + me._classes( '_new_description' ) + '">' + me.new_description + '</div>' : '';

			var txts = [];
			var tbl = $.yote.util.make_table( me._classes_array( 'new_item_table' ) );
			for( var i=0; i < me.new_columns.length; i++ ) {
			    var nc = me.new_columns[ i ];
			    var field = typeof nc === 'object' ? nc.field : nc;
			    var id = '_new_' + me.ct_id + '_' + me.item.id + '_' + field;
			    if( typeof nc === 'object' ) {
				if( me.new_column_titles[i] ) {
				    tbl.add_param_row( [ me.new_column_titles[ i ], nc.render( id ) ], me._classes_array( 'new_item_row' ), me._classes_array( 'new_item_cell' ) );
				} else {
				    tbl.add_row( [ nc.render( id ) ], me._classes_array( 'new_item_row' ), me._classes_array( 'new_item_cell' ) );
				}
			    } else {
				if( me.new_column_titles[ i ] ) {
				    tbl.add_param_row( [ me.new_column_titles[ i ], '<INPUT TYPE="TEXT" ' + ( me.new_column_placeholders[i] ? ' placeholder="' + me.new_column_placeholders[i] + '"' : '') + ' class="' + me._classes( '_new_item_field' ) + '" id="' + id + '">' ], me._classes_array( 'new_item_row' ), me._classes_array( 'new_item_cell' ) );
				} else {
				    tbl.add_row( [ '<INPUT TYPE="TEXT" ' + ( me.new_column_placeholders[i] ? ' placeholder="' + me.new_column_placeholders[i] + '"' : '') + ' class="' + me._classes( '_new_item_field' ) + '" id="' + id + '">' ], me._classes_array( 'new_item_row' ), me._classes_array( 'new_item_cell' ) );
				}
				txts.push( '#' + id );
			    }
			} //each new column
			bf += tbl.get_html();
			bf += '<BUTTON type="BUTTON" class="' + me.prefix_classname + '_new_item_btn _ct_new_item_btn" id="_new_' + me.ct_id + '_' + me.item.id + '_b">' + me.new_button + '</BUTTON>';
			$( me.new_attachpoint ).empty().append( bf );


			for( var i=0; i < me.new_columns.length; i++ ) {
			    var nc = me.new_columns[ i ];
			    if( typeof nc === 'object' && nc[ 'after_render' ] ) {
				nc.after_render( '_new_' + me.ct_id + '_' + me.item.id + '_' + nc.field );
			    }
			    else if( typeof nc === 'function' ) {
				nc( false );
			    }
			}

			$.yote.util.button_actions( {
			    button : '#_new_' + me.ct_id +'_' + me.item.id + '_b',
			    texts  : txts,
			    required : me.new_columns_required,
			    required_by_index : me.new_required_by_index,
			    required_by_function : me.new_required_by_function,
			    action : (function(it) { return function() {
				var newitem = it.new_function ? it.new_function() :
				    it.new_object_type == 'obj'  ? $.yote.fetch_root().new_obj() :
				    it.new_object_type == 'root' ? $.yote.fetch_root().new_root_obj() :
				    it.new_object_type == 'user' ? $.yote.fetch_root().new_user_obj() : null;
				var data_hash = {};
				for( var i=0; i < it.new_columns.length; i++ ) {
				    var nc = it.new_columns[ i ];

				    var field = typeof nc === 'object' ? nc.field : nc;
				    var id = '_new_' + me.ct_id + '_' + me.item.id + '_' + field;
				    if( typeof nc === 'object' ) {
					if( nc[ 'on_create' ] )
					    nc.on_create( newitem, id );
				    }
				    else {
					var val = $( '#' + id  ).val();
					data_hash[ nc ] = val;
					if( newitem ) {
					    newitem.set( nc, val );
					}
				    }
				} //each column
				if( newitem ) {
				    if( it.new_addto_function ) {
					it.new_addto_function( newitem );
				    }
				    else {
					it.item.add_to( { name : it.container_name, items : [ newitem ] } );
				    }
				}
				if( it.after_new_fun ) {
				    it.after_new_fun( newitem, data_hash );
				}
				it.refresh();
			    } } )( me )
			} );
		    }
		    else {
			$( me.new_attachpoint ).empty();
		    }
		} //new attacher

		if( me.column_headers && ! me.suppress_table ) {
		    var ch = [];
		    for( var i=0; i < me.column_headers.length; i++ ) {
			ch.push( me.column_headers[ i ] );
		    }
		    if( me.include_remove ) {
			ch.push( me.remove_column_txt );
		    }
		    tab.add_header_row( ch, me._classes_array( 'row' ), me._classes_array( 'cell' ) );
		}

		try {
		    var items = paginate_function();
		    var max = items.length() > me.plimit ? me.plimit : items.length();
		}
		catch( err ) {
		    return;
		}


		if( me.show_count ) {
		    if( max == count ) {
			buf += '<BR>Showing all items<BR>';
		    } else {
			buf += '<BR>Showing ' + (1+me.start)*1 + ' to ' + ( 1*me.start + 1*max ) + ' of ' + count + ' items<BR>';
		    }
		}
		if( me.paginate_type == 'hash' ) {

		    var keys = items.keys();

		    for( var i in keys ) {
			var key = keys[ i ];
			var item = items.get( key );
			if( item ) {
			    var row = [];
			    row.push( typeof me.columns[ 0 ] == 'function' ?
				      me.columns[ 0 ]( item, true ) :
				      typeof me.columns[ 0 ] == 'object' ?
				      me.columns[ 0 ][ 'render' ]( item, key )
				      : key );

			    for( var j = 1 ; j < me.columns.length; j++ ) {
				var ctype = typeof me.columns[ j ];
				if( ctype == 'string' ) {
				    if( me.columns[ j ].charAt(0) == '*' ) {
					me.columns[j] = $.yote.util.col_edit( me.columns[j].substring(1) );
					ctype = 'function';
				    }
				    else if( me.columns[ j ].charAt(0) == '^' ) {
					me.columns[j] = $.yote.util.check_edit( me.columns[j].substring(1) );
					ctype = 'function';
				    }
				    else if( me.columns[ j ].charAt(0) == '~' ) {
					(function(str) {
					    me.columns[j] = function( item, is_prep ) {
						if( is_prep ) {
						    var nm = "__ItemReg_" + item.id;
						    $.yote.util.register_item( nm, item );
						    str.replace( /$$/g, nm );
						    return str;
						}
					    }
					})( me.columns[j].substring(1) );
					ctype = 'function';
				    }
				}
				row.push( ctype == 'function' ?
					  me.columns[ j ]( item, true ) :
					  ctype == 'object' ?
					  me.columns[ j ][ 'render' ]( item, key )
					  :item.get( me.columns[ j ] )
					);
			    }
			    if( me.include_remove ) {
				row.push( '<BUTTON type="BUTTON" id="remove_' + me.ct_id + '_' + item.id + '_b">' + me.remove_btn_txt + '</BUTTON>' );
			    }
			    if( me.suppress_table ) {
				buf += row.join('');
			    }
			    else {
				tab.add_row( row, me._classes_array( 'row' ), me._classes_array( 'cell' ) );
			    }
			}
		    }
		} //hash pagination
		else { //list pagination
		    for( var i = 0 ; i < max ; i++ ) {
			var item = items.get( i );
			var row = [];
			for( var j = 0 ; j < me.columns.length; j++ ) {
			    var ctype = typeof me.columns[ j ];
			    if( ctype == 'string') {
				if( me.columns[ j ].charAt(0) == '*' ) {
				    me.columns[j ] = $.yote.util.col_edit( me.columns[j].substring(1) );
				    ctype = 'function';
				}
 				else if( me.columns[ j ].charAt(0) == '~' ) {
				    (function(str) {
					me.columns[j] = function( item, is_prep ) {
						if( is_prep ) {
						    var nm = "__ItemReg_" + item.id;
						    $.yote.util.register_item( nm, item );
						    str = str.replace( /\$\$([^\$]|$)/gm, nm + "$1" );
						    return str;
						}
					}
				    })( me.columns[j].substring(1) );
				    ctype = 'function';
				}
			    }
			    row.push( ctype == 'function' ?
				      me.columns[ j ]( item, true ) :
				      ctype == 'object' ?
				      me.columns[ j ][ 'render' ]( item, me.start + i )
				      : item.get( me.columns[ j ] )
				    );
			} //each col
			if( me.include_remove ) {// && ! me.suppress_table ) {
			    row.push( '<BUTTON class="' + me._classes( '_delete_btn' ) + '" type="BUTTON" id="remove_' + me.ct_id + '_' + i + '_b">' + me.remove_btn_txt + '</BUTTON>' );
			}

			if( me.suppress_table ) {
			    buf += row.join('');
			}
			else {
			    tab.add_row( row, me._classes_array( 'row' ), me._classes_array( 'cell' ) );
			}
		    }
		} //list pagination

		if( items.length() == 0 && me.show_when_empty ) {
		    buf += me.show_when_empty( me.search_terms );
		}
		else {
		    buf += me.suppress_table ? '' : tab.get_html();

		    if( me.start > 0 || items.length() > me.plimit ) {
			buf += '<br>';
			buf += '<BUTTON class="' + me._classes( '_to_start_btn' ) + '" type="button" id="to_start_' + me.ct_id + '_b">&lt;&lt;</BUTTON>';
			buf += ' <BUTTON class="' + me._classes( '_back_btn' ) + '" type="button" id="back_' + me.ct_id + '_b">&lt;</BUTTON>';
			buf += '<BUTTON class="' + me._classes( '_forward_btn' ) + '" type="button" id="forward_' + me.ct_id + '_b">&gt;</BUTTON>';
			buf += ' <BUTTON class="' + me._classes( '_to_end_btn' ) + '" type="button" id="to_end_' + me.ct_id + '_b">&gt;&gt;</BUTTON>';
		    }
		}

		$( me.attachpoint ).empty().append( buf );

		if( me.start > 0 ) {
		    $( '#to_start_' + me.ct_id + '_b' ).click(function() { me.start = 0; me.refresh(); } );
		    var b = me.start - me.plimit;
		    if( b < 0 ) b = 0;
		    $( '#back_' + me.ct_id + '_b' ).click(function() { me.start = b; me.refresh(); } );
		}
		else {
		    $( '#to_start_' + me.ct_id + '_b' ).attr( 'disabled', 'disabled' );
		    $( '#back_' + me.ct_id + '_b' ).attr( 'disabled', 'disabled' );
		}

		if( items.length() > me.plimit ) {
		    var e = 1 * ( me.start + me.plimit );
		    if( e > count ) {
			e = count - me.plimit;
		    }
		    $( '#forward_' + me.ct_id + '_b' ).click(function() {
			me.start = e; me.refresh()
		    } );
		    $( '#to_end_' + me.ct_id + '_b' ).click(function() { me.start = 1 * (count - me.plimit); me.refresh(); } );
		}
		else {
		    $( '#to_end_' + me.ct_id + '_b' ).attr( 'disabled', 'disabled' );
		    $( '#forward_' + me.ct_id + '_b' ).attr( 'disabled', 'disabled' );
		}

		if( me.display_search_box ) {
		    var srch_txt = '#_search_txt_' + me.ct_id;
		    var clnup_ex = {};
		    clnup_ex[ srch_txt ] = 1;
		    $.yote.util.button_actions( {
			button : '#_search_btn_' + me.ct_id,
			texts  : [ srch_txt ],
			required : [],
			cleanup_exempt : clnup_ex,
			action : (function(it) { return function() {
			    var searching = $( srch_txt ).val();
			    if( searching.match( /\S/ ) ) {
				it.search_terms = $( srch_txt ).val().split( /[ ,;]+/ );
			    } else {
				it.search_terms = [];
			    }
			    it.refresh();
			} } )( me )
		    } );
		}

		if( me.paginate_type == 'hash' ) {
		    for( var i in keys ) {
			var key = keys[ i ];
			var item = items.get( key );
			if( typeof me.columns[ 0 ] == 'function' ) {
			    me.columns[ 0 ]( item, false, key );
			}
			else if( typeof me.columns[ 0 ] == 'object' && me.columns[ 0 ][ 'after_render' ] ) {
			    me.columns[ 0 ][ 'after_render' ]( item, key );//, function( newstart, key ) { me.refresh(); } );
			}

			for( var j = 1 ; j < me.columns.length; j++ ) {
			    if( typeof me.columns[ j ] == 'function' ) {
				me.columns[ j ]( item, false, key );
			    }
			    else if( typeof me.columns[ j ] == 'object'  && me.columns[ j ][ 'after_render' ] ) {
				me.columns[ j ][ 'after_render' ]( item, key );//function( newstart, key ) { me.refresh(); } );
			    }
			}
			if( me.include_remove ) {
			    $( '#remove_' + me.ct_id + '_' + i + '_b' ).click((function(it,idx) { return function() {
				if( me.remove_fun ) {
				    me.remove_fun( it, me.start + idx );
				} else {
				    me.item.remove_from( { name : me.container_name, items : [ it ] } );
				}
				var to = me.start - 1;
				if( to < 0 ) to = 0;
				me.start = to;
				me.refresh();
			    } } )( item, i ) );
			}
		    } //each row again

		}
		else {
		    for( var i = 0 ; i < max ; i++ ) {
			var item = items.get( i );
			for( var j = 0 ; j < me.columns.length; j++ ) {
			    if( typeof me.columns[ j ] == 'function' ) {
				me.columns[ j ]( item, false );
			    }
			    else if( typeof me.columns[ j ] == 'object'  && me.columns[ j ][ 'after_render' ] ) {
				me.columns[ j ][ 'after_render' ]( item, me.start + i );
			    }
			}
			if( me.include_remove ) {
			    $( '#remove_' + me.ct_id + '_' + i + '_b' ).click((function(it,idx) { return function() {
				if( me.remove_fun ) {
				    me.remove_fun( it, me.start + idx );
				} else {
				    me.item.remove_from( { name : me.container_name, items : [ it ] } );
				}
				var to = me.start - 1;
				if( to < 0 ) to = 0;
				me.start = to;
				me.refresh();
			} } )( item, i ) );
			}
		    } //each row again
		}

		me.after_render( items );

		if( items.length() == 0 && me.after_render_when_empty ) {
		    me.after_render_when_empty( me.search_terms );
		}
	    } //refresh
	}; //define cgt
	ct.refresh();
	if( ct.after_load ) ct.after_load();

	return ct;
    }, //control_table


    // -------------------------- THE 'new' simpler templating system ---------------------------------

/*
  <SCRIPT>
  register_tempates( {
     name       : function() { return user.get_name(); }, //the text is analyzed for further templates, etc
     greeting   : "Hello <b>$name</b>", //how do I find the source of the name? push pop stack for variables?
     greeet_all : "<div><h2>Greet all the users</h2> @greeting</div>"
  } );
  </SCRIPT>
  <BODY>
     <DIV yote_template="greeting"></DIV>
     <DIV yote_template="greet_all"></DIV>


  // should there be something like raw html with a template class that becomes hidden and cloned?

  Here is the thing. You might have :
     An object connected to an other object as a variable that is selected by a select
     A variable connected to the object and edited by an input Text
     A variable connected to the object and edited by a checkbox

     A list of objects to show. The list is connected to an object.


  In each case, you have an object in focus. How do you get the first object?
  how is this bootstrapped??

  Editing templates as yote variables, too?

  default variable  - stack
  iterator variable - stack

*/

    templates : {},
    functions : {},
    default_value_stack : [],
    iter_value_stack : [],
    recursive_block : [], //TODO

    register_template:function( key, value ) {
	$.yote.util.templates[ key ] = value;
    }, //register template

    register_templates:function( hash ) {
	var name, val;
	for( name in hash ) {
	    $.yote.util.register_template( name, hash[ name ] );
	}
    }, //register_template

    register_function:function( key, value ) {
	$.yote.util.functions[ key ] = value;
    },

    register_functions:function( hash ) {
	var name, val;
	for( name in hash ) {
	    $.yote.util.register_function( name, hash[ name ] );
	}
    }, //register_function

    fill_template:function( template_name, default_var, default_parent, hash_key_or_index ) {
	var template = $.yote.util.templates[ template_name ];
	if( ! template ) { return ''; }

	var template_id = $.yote.util.next_id();

	return $.yote.util.fill_template_text( template, default_var, default_parent, hash_key_or_index );
    }, //fill_template

    _template_parts:function( txt, sigil, template ) {
	var start = txt.indexOf( '<' + sigil );
	var end   = txt.indexOf( sigil.split('').reverse().join('') + '>' );
	var len   = sigil.length + 1;
	if( end < start ) {
	    console.log( "Template error for '"+template+"' : unable to find close of <" + sigil );
	    return;
	}
	return [ txt.substring( 0, start ), 
		 txt.substring( start + len, end ).trim(), 
		 txt.substring( end+len ) ];
    }, //_template_parts

    fill_template_text:function( template, default_var, default_parent, hash_key_or_index ) {
	var text_val = typeof template === 'function' ? template() : template;

	while( text_val.indexOf( '<$$' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '$$', template );
	    text_val = parts[ 0 ] + 
		$.yote.util.fill_template( parts[ 1 ], default_var, default_parent, hash_key_or_index ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<$@' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '$@', template );
	    text_val = parts[ 0 ] + 
		$.yote.util.fill_template_container( parts[ 1 ], default_var, default_parent, hash_key_or_index, false ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<$%' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '$%', template );
	    text_val = parts[ 0 ] + 
		$.yote.util.fill_template_container( parts[ 1 ], default_var, default_parent, hash_key_or_index, true ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<$' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '$', template );
	    text_val = parts[ 0 ] + 
		$.yote.util.fill_template_variable( parts[ 1 ], default_var, default_parent, undefined, hash_key_or_index ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<@' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '@', template );
	    text_val = parts[ 0 ] + 
		$.yote.util.fill_template_list_rows( parts[ 1 ], default_var, default_parent, hash_key_or_index ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<@@' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '@@', template );
	    text_val = parts[ 0 ] + 
		$.yote.util.fill_template_list_in_parts( parts[ 1 ], default_var, default_parent, hash_key_or_index ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<%' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '%', template );
	    text_val = parts[ 0 ] + 
		$.yote.util.fill_template_hash_rows( parts[ 1 ], default_var, default_parent, hash_key_or_index ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<?' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '?', template );
	    text_val = parts[ 0 ] + 
		$.yote.util.run_template_function( parts[ 1 ], default_var, default_parent, hash_key_or_index ) +
		parts[ 2 ];
	}
	return text_val;
    }, //fill_template_text

    run_template_function:function( varpart, default_var, default_parent, hash_key_or_index ) {
	var f = $.yote.util.functions[ varpart.trim() ];
	if( f )
	    return $.yote.util.fill_template_text( f( default_var, default_parent, hash_key_or_index ), default_var, default_parent, hash_key_or_index );
	console.log( "Template error. Function '" + varpart + "' not found." );
	return '';
    }, //run_template_function

    fill_template_container:function( varpart, default_var, default_parent, hash_key_or_index, is_hash ) {
	var parts = varpart.split(/ +/);
	
	var main_template     = parts[ 0 ].trim(), 
	    on_empty_template = parts[ 1 ].trim(),
	    host_obj          = $.yote.util._template_var( parts[ 2 ].trim(), default_var, default_parent, hash_key_or_index ),
	    container_name    = parts[ 3 ].trim();
	
	if( host_obj && container_name ) {
	    var container = host_obj.wrap( { collection_name : container_name }, is_hash );
	    if( container.full_size() == 0 ) {
		return $.yote.util.fill_template( on_empty_template, default_var, default_parent, hash_key_or_index );
	    }
	    return $.yote.util.fill_template( main_template, container, default_parent, hash_key_or_index );
	}
	return '';
    }, //fill_template_container

    fill_template_list_rows:function( varpart, default_var, default_parent, hash_key_or_index ) {
	var parts           = varpart.split(/ +/);
	var row_template    = parts[ 0 ].trim(), 
	    pagination_size = parts[ 1 ].trim();
	// assumes default var is a list
	if( default_var && default_var.to_list )
	    return default_var.to_list().map(function(it,idx){ return $.yote.util.fill_template( row_template, it, default_var, idx )} ).join('');
	console.log( "Template error for '"+row_template+"' : default_var passed in is not a list " );
	return '';
    },


    fill_template_hash_rows:function( varpart, default_var, default_parent, hash_key_or_index ) {
	var parts           = varpart.split(/ +/);
	var row_template    = parts[ 0 ].trim(), 
	    pagination_size = parts[ 1 ].trim();
	// assumes default var is a hash
	if( default_var && default_var[ 'to_hash' ] ) {
	    var hash = default_var.to_hash();
	    var keys = Object.keys( hash );
	    keys.sort();
	    if( default_var[ 'sort_reverse' ] ) keys.reverse();
	    return keys.map(function(key,idx){ 
		return $.yote.util.fill_template( row_template, hash[key], default_parent, key );
	    } ).join('');
	}
	console.log( "Template error for '"+row_template+"' : default_var passed in is not a hash " );
	return '';
    },

    fill_template_list_in_parts:function( varpart, default_var, default_parent, hash_key_or_index ) {
	var parts         = varpart.split(/ +/);

	var before_template = parts[ 0 ].trim(),
	    row_template = parts[ 1 ].trim(),
	    after_template = parts[ 2 ].trim(),
            empty_list_template = parts[ 3 ].trim();


	if( parts.length == 5 ) { // <@ before_template row_template after_template emptylisttemplate list_object @>
	    var list_obj = $.yote.util._template_var( parts[ 4 ].trim(), default_var, default_parent, hash_key_or_index );
	    if( list_obj ) {
		var l = list_obj.to_list();
		if( l.length == 0 )
		    return $.yote.util.fill_template( empty_list_template, default_var, default_parent, hash_key_or_index );
		return $.yote.util.fill_template( before_template, default_var, default_parent, hash_key_or_index ) +
		    list_obj.to_list().map(function(it,idx){ return $.yote.util.fill_template( row_template, it, list_obj, idx )} ).join('') +
		    $.yote.util.fill_template( after_template, default_var, default_parent, hash_key_or_index );
	    }
	    else { //it actually is an array
		if( l.length == 0 )
		    return $.yote.util.fill_template( empty_list_template, default_var, default_parent, hash_key_or_index );
		return $.yote.util.fill_template( before_template, default_var, default_parent, hash_key_or_index ) +
		    list_obj.map(function(it,idx){ return $.yote.util.fill_template( row_template, it, list_obj, idx )} ).join('') +
		    $.yote.util.fill_template( after_template, default_var, default_parent, hash_key_or_index );
	    }
	    return '';
	}
	else if( parts.length == 6 ) { // <@ before_template row_template after_template emptylisttemplate parent_object list_in_parent_object @>
	    var host_obj = $.yote.util._template_var( parts[ 4 ].trim(), default_var, default_parent, hash_key_or_index );
	    var list_obj   = host_obj.get( parts[ 5 ].trim() );
	    if( list_obj ) {
		var l = list_obj.to_list();
		if( l.length == 0 )
		    return $.yote.util.fill_template( empty_list_template, default_var, default_parent, hash_key_or_index );
		return $.yote.util.fill_template( before_template, default_var, default_parent, hash_key_or_index ) +
		    l.map(function(it,idx){return $.yote.util.fill_template( row_template, it, host_obj, idx )}).join('') +
		    $.yote.util.fill_template( after_template, default_var, default_parent, hash_key_or_index );
	    }
	    return $.yote.util.fill_template( empty_list_template, default_var, default_parent, hash_key_or_index );
	}
	return '';
    }, //fill_template_list_in_parts


    fill_template_hash_in_parts:function( varpart, default_var, default_parent, hash_key_or_index ) {
	var parts         = varpart.split(/ +/);

	var before_template = parts[ 0 ].trim(),
	    row_template = parts[ 1 ].trim(),
	    after_template = parts[ 2 ].trim(),
            empty_hash_template = parts[ 3 ].trim();

	if( parts.length == 5 ) { // <% beforerowstemplate rowtemplate afterrowstemplate template_for_empty hash_object %>
	    var hash_obj = $.yote.util._template_var( parts[ 4 ].trim(), default_var, default_parent, hash_key_or_index );
	    if( hash_obj ) {
		if( hash_obj.to_hash ) { //its a yote object that is a hash
		    var hash = hash_obj.to_hash();
		    var keys = Object.keys( hash );
		    keys.sort();
		    if( hash_obj.sort_reverse ) keys.reverse();

		    if( Object.size( keys ) == 0 )
			return $.yote.util.fill_template( empty_hash_template, default_var, default_parent, hash_key_or_index );
		    return $.yote.util.fill_template( before_template, default_var, default_parent, hash_key_or_index ) +
			keys.map(function(it,idx){ return $.yote.util.fill_template( row_template, hash[it], hash_obj, it )} ).join('') +
			$.yote.util.fill_template( after_template, default_var, default_parent, hash_key_or_index );
		}
		else { //it actually is a hash
		    var keys = Object.keys( hash_obj );
		    if( Object.size( keys ) == 0 )
			return $.yote.util.fill_template( empty_hash_template, default_var, default_parent, hash_key_or_index );
		    return  $.yote.util.fill_template( before_template, default_var, default_parent, hash_key_or_index ) +
			keys.map(function(it,idx){return $.yote.util.fill_template( row_template, hash_obj[ it ], list_obj, it )}).join('') +
			$.yote.util.fill_template( after_template, default_var, default_parent, hash_key_or_index );
		}
	    }
	    return $.yote.util.fill_template( empty_hash_template, default_var, default_parent, hash_key_or_index );
	} //if passed in an object that is or yields an array
	else if( parts.length == 6 ) { // <% beforerowstemplate rowtemplate afterrowstemplate template_for_empty parent_object list_in_parent_object %>
	    var host_obj = $.yote.util._template_var( parts[ 4 ].trim(), default_var, default_parent, hash_key_or_index );
	    var hash_obj   = host_obj.get( parts[ 5 ].trim() );
	    if( hash_obj ) {
		var hash = hash_obj.to_hash();
		var keys = Object.keys( hash );
		if( keys.length == 0 )
			return $.yote.util.fill_template( empty_hash_template, default_var, default_parent, hash_key_or_index );
		return $.yote.util.fill_template( before_template, default_var, default_parent, hash_key_or_index ) +
		    keys.map(function(it,idx){return $.yote.util.fill_template( row_template, hash[ it ], host_obj, it )}).join('') +
		    $.yote.util.fill_template( after_template, default_var, default_parent, hash_key_or_index );
	    }
	    return '';
	}
	return '';
    }, //fill_template_hash_in_parts

    _template_var:function( targ, default_var, default_parent, template_id, hash_key_or_index ) {
	var tlist = targ.split(/[\.]/);
	var subj = tlist[0];
	var subjobj;
	if( subj == 'acct' )      subjobj = $.yote.fetch_account();
	else if( subj == 'root' ) subjobj = $.yote.fetch_root();
	else if( subj == 'app' )  subjobj = $.yote.fetch_app();
	else if( subj == 'id' )   subjobj = template_id;
	else if( subj == '_' )    subjobj = default_var;
	else if( subj == '__' )   subjobj = default_parent;
	else subjobj = this.registered_items[ subj ];

	if( subjobj ) {
	    for( i=1; i<tlist.length; i++ ) {
		subjobj = subjobj.get( tlist[i] );
	    }
	    return subjobj;
	}
	return subj;
    },

    fill_template_variable:function( varcmd, default_var, default_parent, template_id, hash_key_or_index ) {
	var cmdl = varcmd.split(/ +/); //yikes, this split suxx.use regex
	var cmd  = cmdl[0].toLowerCase();
	var subj = cmdl[1];
	var fld  = cmdl[2];
	if( cmd == 'hash_key' ) {
	    return hash_key_or_index;
	}
	var subjobj = $.yote.util._template_var( subj, default_var, default_parent, template_id, hash_key_or_index );
	if( cmd == 'edit' ) {
	    if( ! subjobj ) return '';
	    return '<span class="yote_panel" ' + (fld.charAt(0) == '#' ? ' as_html="true" ' : '' ) + ' after_edit_function="*function(){$.yote.util.refresh_ui();}" item="$$' + subjobj.id + '" field="' + fld + '"></span>';
	}
	else if( cmd == 'show' ) {
	    if( ! subjobj ) return '';
	    return '<span class="yote_panel" no_edit="true" ' + (fld.charAt(0) == '#' ? ' as_html="true" ' : '' ) + ' item="$$' + subjobj.id + '" field="' + fld + '"></span>';
	}
	else if( cmd == 'checkbox' ) {
	    if( ! subjobj ) return '';
	    return '<span class="yote_panel" use_checkbox="true" after_edit_function="*function(){$.yote.util.refresh_ui();}" item="$$' + subjobj.id + '" field="' + fld + '"></span>';
	}
	else if( cmd == 'switch' ) {
	    var oid = default_var ? default_var.id : 'undefined';
	    var poid = default_parent ? default_parent.id : 'undefined';
	    return '<span class="yote_panel" use_checkbox="true" bare="true" after_edit_function="' + subj + '" item="$$' + oid + '" parent="$$' + poid + '" template_id="' + template_id + '" hash_key_or_index="' + hash_key_or_index +'" ' + (fld ? ' checked="checked"' : '' ) + '></span>';
	}
	else if( cmd == 'select' ) {
	    if( ! subjobj ) return '';
	    parts = /^\s*\S+\s+\S+\s+\S+\s+(.*)/.exec( varcmd );
	    listblock = parts[ 1 ];
	    return '<span class="yote_panel" use_select="true" sel_list="' + listblock + '" after_edit_function="*function(){$.yote.util.refresh_ui();}" item="$$' + subjobj.id + '" field="' + fld + '"></span>';
	}
	else if( cmd == 'selectobj' ) {
	    cmdl = varcmd.split(/ +/);
	    var lst = $.yote.util._template_var( cmdl[3].trim(), default_var, default_parent, template_id );
	    if( lst ) {
		if( ! subjobj ) return '';
		return '<span class="yote_panel" use_select_obj="true" list_field="' + cmdl[4].trim() + '" list_obj="$$' + lst.id + '" after_edit_function="*function(){$.yote.util.refresh_ui();}" item="$$' + subjobj.id + '" field="' + fld + '"></span>';
	    }
	    console.log( "Could not find '" + cmdl[3] + "'" );
	    return '';
	}
	else if( cmd == 'button' ) {
	    parts = /^\s*(\S+)\s+(\S+)\s*(.*)/.exec( varcmd );
	    var item   = default_var;
	    var parent = default_parent;
	    return '<button type="BUTTON" ' + ( item ? ' item="$$' + item.id + '"' : '' ) +  ( parent ? ' parent="$$' + parent.id + '"' : '' ) + ' class="yote_button" action="' + subj.trim() +'">' + cmdl[2].trim() + '</button>'; //needs to insert an id for itself and register the action
	    // also need a pagination object which will work with the tempates and we can finally rid ourselves of control_table bigcodyness
	}
	else if( cmd == 'action_link' ) {
	    parts = /^\s*(\S+)\s+(\S+)\s*(.*)/.exec( varcmd );
	    var item   = default_var;
	    var parent = default_parent;
	    return '<a href="#" ' + ( item ? ' item="$$' + item.id + '"' : '' ) +  ( parent ? ' parent="$$' + parent.id + '"' : '' ) + ' class="yote_action_link" action="' + subj.trim() +'">' + cmdl[2].trim() + '</a>'; //needs to insert an id for itself and register the action
	    // also need a pagination object which will work with the tempates and we can finally rid ourselves of control_table bigcodyness
	}
	console.log( "template variable command '" + varcmd + '" not understood' );
	return '';
    }, //fill_template_variable

/*
  Template sigils :
     <$$ template name $$>  <--- fills with template
     <$                 $>  <--- fills with variable
     <% template_before_rows row_template template_after_rows tempate_for_empty_hash registered_host_object hashname_in_host_object %>  <--- fills with template
     <@ template_before_rows row_template template_after_rows tempate_for_empty_list registered_host_object listname_in_host_object @>  <--- fills with template

   Inside the variable fill is a particular syntax

      * id                     ( id of this template _instance_ )
      * show    item   field   ( prepend field with # if it is to be as html )
      * edit    item   field   ( prepend field with # if it is to be as html )
      * select     object field [json list]
      * selectobj  object field list_of_objs field_of_list_objs
      * checkbox  object  field  (  makes checkbox for a field on an object
      * switch  object  function  ( runs function on change )
      * button templateaction "title"  ( runs the function registered as a template and passes in  _, __ )
      * action_link templateaction "title"  ( runs the function registered as a template and passes in  _, __ )

      * radio   field ( like select with choose 1 ... implement at some point )


  ( default var as _ , parent as __  )


     <@ templatename list @>
     <@ templatename obj field @>
     <? command ?>   run the restigered function and include its text result in the html
   Applies the template to each item in the list, concatinating the results together.



*/

}//$.yote.util
