/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Version 0.023
 */
$.yote.util = {
    ids:0,

    button_actions:function( args ) {
	var but         = args[ 'button' ];
	var action      = args[ 'action' ] || function(){};
	var on_escape   = args[ 'on_escape' ] || function(){};
	var texts       = args[ 'texts'  ] || [];
	var req_texts   = args[ 'required' ];
	var exempt      = args[ 'cleanup_exempt' ] || {};
	var extra_check = args[ 'extra_check' ] || function() { return true; }

	var check_ready = (function(rt,te,ec) { return function() {
	    var t = rt || te;
	    var ecval = ec();
	    for( var i=0; i<t.length; ++i ) {
		if( ! $( t[i] ).val().match( /\S/ ) ) {
	    	    $( but ).attr( 'disabled', 'disabled' );
		    return false;
		}
	    }
	    $( but ).attr( 'disabled', ! ecval );
	    return ecval;
	} } )( req_texts, texts, extra_check ) // check_ready

	for( var i=0; i<texts.length - 1; ++i ) {
	    $( texts[i] ).keyup( function() { check_ready(); return true; } );
	    $( texts[i] ).keypress( (function(box,oe) {
		return function( e ) {
		    if( e.which == 13 ) {
			$( box ).focus();
		    } else if( e.which == 27 ) {
			oe();
		    }
		} } )( texts[i+1], on_escape ) );
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

	$( texts[texts.length - 1] ).keyup( function() { check_ready(); return true; } );
	$( texts[texts.length - 1] ).keypress( (function(a,oe) { return function( e ) {
	    if( e.which == 13 ) {
		a();
	    } else if( e.which == 27 ) {
		eo();
	    } } } )(act,on_escape) );

	$( but ).click( act );

	check_ready();

	return check_ready;

    }, //button_actions

    next_id:function() {
        return 'yidx_'+this.ids++;
    },

    implement_edit:function( item, field ) {
	var id_root  = item.id + '_' + field;
	var div_id   = 'ed_'  + id_root;
	var txt_id   = 'txt_' + id_root;
	var canc_id  = 'txc_' + id_root;
	var go_id    = 'txb_' + id_root;

	var go_normal = function() {
	    $( '#' + div_id ).removeClass( 'edit_ready' );
	    $( '#' + div_id ).off( 'click' );
	} //implement_edit.go_normal

	var stop_edit = function() {
	    $( '#' + div_id ).empty().append( item.get( field ) );
	    go_normal();
	    $.yote.util.implement_edit( item, field );
	} //implement_edit.stop_edit

	var apply_edit = function() {
	    var val = $( '#' + txt_id ).val();
	    item.set( field, val );
	    stop_edit();
	}

	var go_edit = function() {
	    var rows = 2;
	    var val = item.get( field );
	    if( val != null ) {
		rows = Math.round( val.length / 25 );
	    }
	    if( rows < 2 ) { rows = 2; }
	    var w = $( '#' + div_id ).width() + 40;
	    if( w < 100 ) w = 100;
	    var h = $( '#' + div_id ).height() + 20;
	    $( '#' + div_id ).empty().append( '<textarea STYLE="width:' + w + 'px;' +
					      'height:' + h + 'px;" class="in_edit_same" id="' + txt_id + '">' + val + '</textarea><BR>' +
					'<button class="cancel" type="button" id="' + canc_id + '">cancel</button> ' +
					'<button class="go" type="button" id="' + go_id + '">Go</button> ' );
	    $( '#' + txt_id ).keyup( function(e) {
		if( item.get( field ) == $( '#' + txt_id ).val() ) {
		    $( '#' + txt_id ).addClass( 'in_edit_same' );
		    $( '#' + txt_id ).removeClass( 'in_edit_changed' );
		} else {
		    $( '#' + txt_id ).removeClass( 'in_edit_same' );
		    $( '#' + txt_id ).addClass( 'in_edit_changed' );
		}
	    } );
	    $( '#' + txt_id ).keypress( function(e) {
		if( e.keyCode == 27 ) { //escape like cancel
		    stop_edit();
		}
	    } );
	    $( '#' + go_id ).click( apply_edit );
	    $( '#' + canc_id ).click( stop_edit );
	    $( '#' + txt_id ).focus();
	    $( '#' + div_id ).off( 'click' );
	    $( '#' + div_id ).off( 'mouseenter' );
	    $( '#' + div_id ).off( 'mouseleave' );
	} //implement_edit.go_edit

	var show_edit = function() {
	    if( $( '#' + canc_id ).length == 0 ) {
		$( '#' + div_id ).addClass( 'edit_ready' );
		$( '#' + div_id ).click( go_edit );
	    }
	}

	$( '#' + div_id ).mouseleave( function() {go_normal() } ).mouseenter( function() { show_edit() } );
    }, //implement_edit

    prep_edit:function( item, fld, extra ) {
	var val = item.get( fld ) || '';
	var exr = extra || '';
	var div_id   = 'ed_' + item.id + '_' + fld;
	return '<DIV CLASS="input_div" id="' + div_id + '">' + val + '</div>';
    }, //prep_edit


    stage_text_field:function(attachpoint,yoteobj,fieldname) {
        var val = yoteobj.get(fieldname);
        var idname = this.next_id();
        attachpoint.append( '<input type="text" id="' + idname + '">' );
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
        attachpoint.append( '<textarea cols="'+cols+'" rows="'+rows+'" id="' + idname + '"></textarea>' );
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
        attachpoint.append( '<SELECT id="'+idname+'">' + (include_none == true ? '<option value="">None</option>' : '' ) + '</select>' );
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

    build_select_txt:function( args ) {
	var items = args[ 'items' ], text = args[ 'text' ], val = args[ 'val' ], id = args[ 'id' ];
	var dflt = args[ 'default' ];
	if( items.length() == 0 ) { return dflt; }
	var buf = '<SELECT id="' + id + '" ' + args[ 'extra' ] + '>';
	if( args[ 'include_none' ] ) { buf += '<OPTION value="">None</OPTION>'; }
	for( var i=0; i < items.length(); i++ ) {
	    var item = items.get( i );
	    buf += '<OPTION value="' + val( item, i ) + '">' + text( item ) + '</OPTION>';
	}
	return buf + '</SELECT>';
    }, //build_select_txt

    make_select:function(attachpoint,list,list_fieldname) {
	var idname = this.next_id();
        attachpoint.append( '<select id="'+idname+'"></select>' );
	for( var i in list ) {
	    var item = list[i];
	    $( '#'+idname ).append( '<option value='+item.id+'>'+item.get(list_fieldname)+'</option>' );
	}
	return $( '#' + idname );
    },
    make_table:function(extra) {
	var xtr = extra ? extra : '';
	return {
	    html:'<table ' + xtr + '>',
	    next_row_class:'class="even-row" ',
	    add_header_row : function( arry, extra_row, extra_headers ) {
		var xtr_row = extra_row ? extra_row : '';
		var xtr_headers = extra_headers ? extra_headers : '';
		this.html = this.html + '<tr ' + this.next_row_class + xtr_row + '>';
		if( this.next_row_class == 'class="even-row" ' ) {
		    this.next_row_class = 'class="odd-row" ';
		} else {
		    this.next_row_class = 'class="even-row" ';
		}
		var cls = 'class="even-col" ';
		for( var i=0; i<arry.length; i++ ) {
		    var colname = typeof arry[i] === 'function' ? arry[i]() : arry[i];
		    this.html = this.html + '<th ' + cls + xtr_headers + '>' + colname + '</th>';
		    if( cls == 'class="even-col" ' ) {
			cls = 'class="odd-col" ';
		    } else {
			cls = 'class="even-col" ';
		    }
		}
		this.html = this.html + '</tr>';
		return this;
	    },
	    add_row : function( arry, extra_row, extra_headers ) {
		var xtr_row = extra_row ? extra_row : '';
		this.html = this.html + '<tr ' + this.next_row_class + xtr_row + '>';
		if( this.next_row_class == 'class="even-row" ' ) {
		    this.next_row_class = 'class="odd-row" ';
		} else {
		    this.next_row_class = 'class="even-row" ';
		}

		var cls = 'class="even-col" ';
		for( var i=0; i<arry.length; i++ ) {
		    if( extra_headers ) {
			this.html = this.html + '<td ' + cls + extra_headers[i] + '>' + arry[i] + '</td>';
		    } else {
			this.html = this.html + '<td ' + cls + '>' + arry[i] + '</td>';
		    }
		    if( cls == 'class="even-col" ' ) {
			cls = 'class="odd-col" ';
		    } else {
			cls = 'class="even-col" ';
		    }
		}
		this.html = this.html + '</tr>';
		return this;
	    },
	    add_param_row : function( arry ) {
		this.html = this.html + '<tr ' + this.next_row_class + '>';
		if( this.next_row_class == 'class="even-row" ' ) {
		    this.next_row_class = 'class="odd-row" ';
		} else {
		    this.next_row_class = 'class="even-row" ';
		}
		if( arry.length > 0 ) {
		    this.html = this.html + '<th class="even-col">' + arry[0] + '</th>';
		}
		var cls = 'class="odd-col" ';
		for( var i=1; i<arry.length; i++ ) {
		    this.html = this.html + '<td ' + cls + '>' +  arry[i] + '</td>';
		    if( cls == 'class="even-col" ' ) {
			cls = 'class="odd-col" ';
		    } else {
			cls = 'class="even-col" ';
		    }
		}
		this.html = this.html + '</tr>';
		return this;
	    },
	    get_html : function() { return this.html + '</table>'; }
	}
    }, //make_table

    // builds a table that paginates through a list
    make_paginatehash_table:function( arg ) {
	return (function( args ){

	    var ptab = {
		obj          : args[ 'obj' ],
		list_name    : args[ 'list_name' ],
		size         : args[ 'size' ] || 100,
		col_names    : args[ 'col_names' ],
		title        : args[ 'title' ] || '',
		col_funs     : args[ 'col_functions' ],
		attach_point : args[ 'attach_point' ]
	    };

	    ptab[ 'show' ] = function( start_pos ) {
		if( ptab[ 'attach_point' ] ) {
		    $( ptab[ 'attach_point' ] ).empty().append( ptab.build_html( start_pos ) );
		    $( '#forward_' + ptab.obj.id ).click(function(){
			ptab.show( start_pos + ptab.size );
		    });
		    $( '#back_' + ptab.obj.id ).click(function(){
			var x = start_pos - ptab.size;
			ptab.show( x > 0 ? x : 0 );
		    });

		}
	    };

	    ptab[ 'build_html' ] = function(start_pos) {
		var start = start_pos ? start_pos : 0;
		var tab = $.yote.util.make_table();
		if( ptab.col_names ) {
		    tab.add_header_row( ptab.col_names );
		}
		var hash = ptab.obj[ 'paginate_hash' ]( [ ptab.list_name, ptab.size + 1, start ] );
		var max = hash.length() < ptab.size ? hash.length() : ptab.size;
		var keys = hash.keys();
		for( var i=0; i < max ; i++ ) {
		    var key = keys[ i ];
		    var val = hash.get( key );
		    if( ptab.col_funs ) {
			var arry = [];
			for( var j=0; j < ptab.col_funs.length; j++ ) {
			    var fun = ptab.col_funs[ j ];
			    arry.push( fun( key, val ) );
			}
			tab.add_row( arry );
		    }
		    else {
			tab.add_row( [ key, val ] );
		    }
		}

		var buf = ptab.title + tab.get_html();

		if( start > 0 ) {
		    buf = buf + '<span id="back_' + ptab.obj.id + '" class="btn"><i class="icon-fast-backward"></i></span>';
		    if( hash.length() > max ) {
			buf = buf + '<span id="forward_' + ptab.obj.id + '" class="btn"><i class="icon-fast-forward"></i></span>';
		    }
		    else {
			buf = buf + '<span class="btn"><i class="icon-fast-forward icon-white"></i></span>';
		    }
		}
		else {
		    if( hash.length() > max ) {
			buf = buf + '<span class="btn"><i class="icon-fast-backward icon-white"></i></span>';
			buf = buf + '<span id="forward_' + ptab.obj.id + '" class="btn"><i class="icon-fast-forward"></i></span>';
		    } else {
			//nothing to do
		    }
		}
		return buf;
	    };

	    ptab[ 'attach_to' ] = function( attach_point ) {
		ptab[ 'attach_point' ] = attach_point;
		ptab.show( 0 );
	    };

	    if( ptab[ 'attach_point' ] ) {
		ptab.show( 0 );
	    }

	    return ptab;
	})( arg );
    }, //make_paginatehash_table


    login_control:function( args ) {
	var lc = {
	    attachpoint      : args[ 'attachpoint' ],
	    msg_function     : args[ 'msg_function' ]              || function(m,c){ c ? $( '#login_msg' ).removeClass().addClass( c ) : '';$( '#login_msg' ).empty().append( m ); },
	    log_in_status    : args[ 'log_in_status_attachpoint' ] || '#logged_in_status',
	    after_login_fun  : args[ 'after_login_function' ],
	    after_logout_fun : args[ 'after_logout_function' ],
	    logged_in_test   : args[ 'logged_in_test' ] || function() { return $.yote.is_logged_in(); },
	    logged_in_fail_msg : args[ 'logged_in_fail_msg' ],

	    on_login:function() {
		var thislc = this;
		$( thislc.attachpoint ).empty();
		$( thislc.log_in_status ).empty().append(
		    'Logged in as ' + $.yote.get_login().get_handle() + '<BR><A href="#" id="logout">Log Out</A>'
		);
		$( '#logout' ).click( function() {
		    thislc.msg_function( 'logged out' );
		    $( thislc.log_in_status ).empty();
		    thislc.on_logout_fun();
		    $.yote.logout();
		    thislc.after_logout_fun();
		} );
	    }, //on_login

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
			$.yote.create_login( $( '#username' ).val(), $( '#pw' ).val(), $( '#em' ).val(),
					     function( msg ) {
						 if( thislc.logged_in_test() == true ) {
						     thislc.msg_function( msg );
						     thislc.on_login_fun();
						     thislc.after_login_fun();
						 } else if( thislc.logged_in_fail_msg ) {
						     thislc.msg_function( thislc.logged_in_fail_msg, 'error' );
						 }
					     },
					     function( err ) {
						 thislc.msg_function( err, 'error' );
					     }  );
		    }
		} );

	    },

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
			'<input type="password" placeholder="Password" id="pw" size="6"> <BUTTON type="BUTTON" id="log_in_b">Log In</BUTTON></P> ' +
			'<A id="create_account_b" class="hotlink" href="#">Create an Account</A> <A id="cancel_b" href="#">[X]</A>' +
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
					  if( thislc.logged_in_test() ) {
					      thislc.on_login_fun();
					      thislc.after_login_fun();
					  } else if( thislc.logged_in_fail_msg ) {
					      thislc.msg_function( thislc.logged_in_fail_msg, 'error' );
					  }
				      },
				      function( err ) {
					  thislc.msg_function( err, 'error' );
				      } );
		    }
		} );

		$( '#create_account_b' ).click( function() { thislc.make_create_login(); } );
	    } //make_login
	};
	lc.on_logout_fun = args[ 'on_logout_function' ] || lc.make_login;
	lc.on_login_fun = args[ 'on_login_fun' ]  || lc.on_login;
	if( lc.logged_in_test() ) {
	    lc.on_login_fun();
	    lc.after_login_fun();
	} else {
	    if( lc.logged_in_fail_msg )
		lc.msg_function( lc.logged_in_fail_msg, 'error' );
	    lc.on_logout_fun();
	    lc.after_logout_fun();
	}

	return lc
    }, //login_control


    col_edit:function( fld, extra ) {
	return function( item, is_prep ) {
	    if( is_prep ) {
		return $.yote.util.prep_edit( item, fld, extra );
	    } else {
		$.yote.util.implement_edit( item, fld );
	    }
	};
    }, //col_edit

    cols_edit:function( flds, titles, extra ) {
	var use_titles = titles || flds;
	return function( item, is_prep ) {
	    if( is_prep ) {
		var tab = $.yote.util.make_table();
		for( var i=0; i<flds.length; i++ ) {
		    tab.add_param_row( [ use_titles[ i ], $.yote.util.prep_edit( item, flds[i], extra ) ] );
		}
		return tab.get_html();
	    } else {
		for( var i=0; i<flds.length; i++ ) {
		    $.yote.util.implement_edit( item, flds[i] );
		}
	    }
	};
    }, //cols_edit

    // this tool is to create a table where the rows correspond to a list in a target
    // objects and the end user can add or remove the rows, or manipulate them
    control_table:function( args ) {
	var ct = {
	    start		: 0,
	    item		: args[ 'item' ],
	    list_name		: args[ 'list_name' ],
	    paginate_type	: args[ 'paginate_type' ] || 'list',
	    paginate_order	: args[ 'paginate_order' ] || 'forward',
	    plimit		: args[ 'plimit' ] || 10,
	    attachpoint		: args[ 'attachpoint' ],
	    column_headers	: args[ 'column_headers' ],
	    columns		: args[ 'columns' ],

	    new_attachpoint    : args[ 'new_attachpoint' ],
	    new_columns        : args[ 'new_columns' ],
	    new_column_titles  : args[ 'new_column_titles' ] || args[ 'new_columns' ],
	    new_function       : args[ 'new_function' ],
	    new_button         : args[ 'new_button' ] || 'New',
	    new_title          : args[ 'new_title' ]  || 'New',

	    after_render   : args[ 'after_render' ]   || function(x) {},
	    table_extra    : args[ 'table_extra' ],
	    suppress_table : args[ 'suppress_table' ] || false,
	    remove_fun     : args[ 'remove_function' ],

	    search         : args[ 'search' ],
	    search_fun     : args[ 'search_function' ], // optional alternate searcdh function
	    search_on      : args[ 'search_on' ], //what search fields to use
	    title          : args[ 'title' ],
	    description    : args[ 'description' ],

	    ct_id   : this.next_id(),
	    terms   : [],
	    refresh : function() {
		var me = this;


		var paginate_function;

		(function(it) {
		    if( it.search && it.terms.length > 0 ) {
			paginate_function = function() {
			    if( it.search_fun ) {
				return it.search_fun( [ it.list_name, it.search_on, it.terms, it.plimit + 1, it.start ] );
			    } else {
				return it.item.search( [ it.list_name, it.search_on, it.terms, it.plimit + 1, it.start ] );
			    }
			}
		    }
		    else {
			paginate_function = function() {
			    if( it.paginate_type == 'hash' ) {
				return it.item.paginate_hash( [ it.list_name, it.plimit + 1, it.start ] );
			    }
			    else if( it.paginate_order == 'forward' ) {
				return it.item.paginate_list( [ it.list_name, it.plimit + 1, it.start ] );
			    }
			    else {
				return it.item.paginate_list_rev( [ it.list_name, it.plimit + 1, it.start ] );
			    }
			}
		    }
		} )( me );


		// calculated
		var count          = me.item.count( me.list_name );

		var buf = me.title + '' + me.description;

		if( me.search ) {
		    buf += '<div id="_search_div">Search <input type="text" id="_search_txt_' + me.ct_id + '"> ' +
			'<button type="button" id="_search_btn_' + me.ct_id + '">Search</button>' +
			'</div>';

		}

		if( ! me.suppress_table ) {
		    var tab = $.yote.util.make_table( me.table_extra );
		}

		if( me.new_attachpoint ) {
		    var bf = me.new_title + '<BR>';

		    var txts = [];
		    var tbl = $.yote.util.make_table();
		    for( var i=0; i < me.new_columns.length; i++ ) {
			var nc = me.new_columns[ i ];
			var field = typeof nc === 'object' ? nc.field : nc;
			var id = '_new_' + me.item.id + '_' + field;
			if( typeof nc === 'object' ) {
			    tbl.add_row( [ me.new_column_titles[ i ], nc.html( id ) ] );
			} else {
			    tbl.add_param_row( [ me.new_column_titles[ i ], '<INPUT TYPE="TEXT" id="' + id + '">' ] );
			}
			txts.push( '#' + id );
		    }
		    bf += tbl.get_html();
		    bf += '<BUTTON type="BUTTON" id="_new_' + me.item.id + '_b">' + me.new_button + '</BUTTON>';
		    $( new_attachpoint ).empty().append( bf );

		    if( me.search ) {
			$.yote.util.button_actions( {
			    button : '#_search_btn_' + me.ct_id,
			    texts  : [ '#_search_txt_' + me.ct_id ],
			    action : (function(it) { return function() {
				it.terms = $( '#_search_txt_' + it.ct_id ).val().split( /[ ,;]+/ );
				it.refresh();
			    } } )( me )
			} );
		    }

		    $.yote.util.button_actions( {
			button : '#_new_' + me.item.id + '_b',
			texts  : txts,
			action : (function(it) { return function() {
			    var newitem = it.new_function();
			    for( var i=0; i < it.new_columns.length; i++ ) {
				var nc = it.new_columns[ i ];
				var field = typeof nc === 'object' ? nc.field : nc;
				var val = $( '#_new_' + it.item.id + '_' + field ).val();
				newitem.set( field, val );
			    }
			    it.refresh();
			} } )( me )
		    } );
		} //new attacher

		if( me.column_headers && ! me.suppress_table ) {
		    var ch = [];
		    for( var i=0; i < me.column_headers.length; i++ ) {
			ch.push( me.column_headers[ i ] );
		    }
		    if( me.remove_fun ) {
			ch.push( 'Delete' );
		    }
		    tab.add_header_row( ch );
		}

		var items = paginate_function();
		console.log( [ 'items', items ] );

		var max = items.length() > me.plimit ? me.plimit : items.length();

		if( me.paginate_type == 'hash' ) {

		    var keys = items.keys();

		    for( var i in keys ) {
			var key = keys[ i ];
			var item = items.get( key );
			var row = [];
			for( var j = 0 ; j < me.columns.length; j++ ) {
			    row.push( typeof me.columns[ j ] == 'function' ?
				      me.columns[ j ]( item, true ) :
				      typeof me.columns[ j ] == 'object' ?
				      me.columns[ jb ][ 'render' ]( item )
				      : item.get( me.columns[ j ] )
				    );
			}
			if( me.remove_fun ) {
			    row.push( '<BUTTON type="BUTTON" id="remove_' + item.id + '_b">Delete</BUTTON>' );
			}
			if( me.suppress_table ) {
			    buf += row.join('');
			}
			else {
			    tab.add_row( row );
			}
		    }
		}
		else {
		    for( var i = 0 ; i < max ; i++ ) {
			var item = items.get( i );
			var row = [];
			for( var j = 0 ; j < me.columns.length; j++ ) {
			    row.push( typeof me.columns[ j ] == 'function' ?
				      me.columns[ j ]( item, true ) :
				      typeof me.columns[ j ] == 'object' ?
				      me.columns[ j ][ 'render' ]( item )
				      : item.get( me.columns[ j ] )
				    );
			}
			if( me.remove_fun && ! me.suppress_table ) {
			    row.push( '<BUTTON type="BUTTON" id="remove_' + item.id + '_b">Delete</BUTTON>' );
			}
			if( me.suppress_table ) {
			    buf += row.join('');
			}
			else {
			    tab.add_row( row );
			}
		    }
		}

		buf += me.suppress_table ? '' : tab.get_html();

		if( me.start > 0 || items.length() > me.plimit ) {
		    buf += '<br>';
		    buf += '<BUTTON type="button" id="to_start_b">&lt;&lt;</BUTTON>';
		    buf += ' <BUTTON type="button" id="back_b">&lt;</BUTTON>';
		    buf += '<BUTTON type="button" id="forward_b">&gt;</BUTTON>';
		    buf += ' <BUTTON type="button" id="to_end_b">&gt;&gt;</BUTTON>';
		}

		$( me.attachpoint ).empty().append( buf );

		if( me.start > 0 ) {
		    $( '#to_start_b' ).click(function() { me.start = 0; me.refresh(); } );
		    var b = me.start - me.plimit;
		    if( b < 0 ) b = 0;
		    $( '#back_b' ).click(function() { me.start = b; me.refresh(); } );
		}
		else {
		    $( '#to_start_b' ).attr( 'disabled', 'disabled' );
		    $( '#back_b' ).attr( 'disabled', 'disabled' );
		}

		if( items.length() > me.plimit ) {
		    var e = me.start + me.plimit;
		    if( e > count ) {
			e = count - me.plimit;
		    }
		    $( '#forward_b' ).click(function() { me.start = e; me.refresh() } );
		    $( '#to_end_b' ).click(function() { me.start = count - me.plimit; me.refresh(); } );
		}
		else {
		    $( '#to_end_b' ).attr( 'disabled', 'disabled' );
		    $( '#forward_b' ).attr( 'disabled', 'disabled' );
		}

		if( me.paginate_type == 'hash' ) {
		    for( var i in keys ) {
			var key = keys[ i ];
			var item = items.get( key );
			for( var j = 0 ; j < me.columns.length; j++ ) {
			    if( typeof me.columns[ j ] == 'function' ) {
				me.columns[ j ]( item, false );
			    }
			    else if( typeof me.columns[ j ] == 'object' ) {
				me.columns[ j ][ 'after_render' ]( item, function( newstart ) { me.refresh(); } );
			    }
			}
			if( me.remove_fun ) {
			    $( '#remove_' + item.id + '_b' ).click((function(it) { return function() {
				me.remove_fun( it );
				var to = me.start - 1;
				if( to < 0 ) to = 0;
				me.start = to;
				me.refresh();
			    } } )( item ) );
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
			    else if( typeof me.columns[ j ] == 'object' ) {
				me.columns[ j ][ 'after_render' ]( item, function( newstart ) { me.refresh(); } );
			    }
			}
			if( me.remove_fun ) {
			    $( '#remove_' + item.id + '_b' ).click((function(it) { return function() {
				me.remove_fun( it );
				var to = me.start - 1;
				if( to < 0 ) to = 0;
				me.start = to;
				me.refresh();
			} } )( item ) );
			}
		    } //each row again
		}

		me.after_render( items );
	    } //refresh
	}; //define cgt
	ct.refresh();

	return ct;
    } //control_table

}//$.yote.util
