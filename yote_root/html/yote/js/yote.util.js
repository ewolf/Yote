/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Version 0.025
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

    register_items:function( hashed_items ) {
	for( var key in hashed_items ) {
	    this.registered_items[ key ] = hashed_items[ key ];
	}
    },

    button_actions:function( args ) {
	var but         = args[ 'button' ];
	var action      = args[ 'action' ] || function(){};
	var on_escape   = args[ 'on_escape' ] || function(){};
	var texts       = args[ 'texts'  ] || [];
	var req_texts   = args[ 'required' ];
	var req_indexes = args[ 'required_by_index' ];
	var req_fun     = args[ 'required_by_function' ];
	var exempt      = args[ 'cleanup_exempt' ] || {};
	var extra_check = args[ 'extra_check' ] || function() { return true; }

	var check_ready = (function(rt,te,ec,re,rf) { return function() {
	    var ecval = ec();
	    var t = rt || te;
	    if( typeof rf === 'function' ) {
		if( rf( te ) != true ) {
		    $( but ).attr( 'disabled', 'disabled' );
		    return false;
		}
	    }
	    else if( typeof re !== 'undefined' ) {
		for( var i=0; i<re.length; ++i ) {
		    if( ! $( te[ re[ i ] ] ).val().match( /\S/ ) ) {
	    		$( but ).attr( 'disabled', 'disabled' );
			return false;
		    }
		}
	    }
	    else {
		for( var i=0; i<t.length; ++i ) {
		    if( ! $( t[i] ).val().match( /\S/ ) ) {
	    		$( but ).attr( 'disabled', 'disabled' );
			return false;
		    }
		}
	    }
	    $( but ).attr( 'disabled', ! ecval );
	    return ecval;
	} } )( req_texts, texts, extra_check, req_indexes, req_fun ); // check_ready

	for( var i=0; i<texts.length - 1; ++i ) {
	    if( $( texts[i] ).prop('type') == 'checkbox' ) {
		$( texts[i] ).click( function() { check_ready(); return true; } );
	    }
	    else {
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

    implement_edit:function( item, field, on_edit_function ) {
	var id_root  = item.id + '_' + field;

	var editor = {
	    'item'  : item,
	    'field' : field,
	    'on_edit_function' : on_edit_function,
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
		$.yote.util.implement_edit( me.item, me.field, me.on_edit_function );
	    }, //implement_edit.stop_edit

	    apply_edit : function() {
		var me = editor;
		var val = $( '#' + me.txt_id ).val();
		if( me.on_edit_function )
		    me.on_edit_function(val,item);
		else
		    me.item.set( me.field, val );
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

    prep_edit:function( item, fld, extra, as_html ) {
	var extr = extra || [];
	var div_id   = 'ed_' + item.id + '_' + fld;
	var txt;
	if( as_html ) {
	    txt = '<DIV CLASS="input_div ' + extr.join(' ') + '" as_html="true" id="' + div_id + '"></div>';
	} else {
	    txt = '<DIV CLASS="input_div ' + extr.join(' ') + '" id="' + div_id + '"></div>';
	}
	return txt;
    }, //prep_edit

    attach_edit_textarea:function( anchor, item, fld, extra ) {
	var val = item.get( fld ) || '';
	var extr = extra || [];
	var div_id   = 'ed_' + item.id + '_' + fld;
	$( anchor ).empty().append( '<textarea CLASS="input_div ' + extr.join(' ') + '" id="' + div_id + '"></textarea>' );
	$( '#' + div_id ).val( val );
	$.yote.util.implement_edit( item, fld ).go_edit();
    }, //attach_edit_textarea

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
	var xtr = args[ 'extra' ] ? args[ 'extra' ] : [];
	var buf = '<SELECT id="' + id + '" class="' + xtr.join(' ') + '">';
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

    // builds a table that paginates through a list
    make_paginatehash_table:function( arg ) {
	return (function( args ){

	    var ptab = {
		obj          : args[ 'obj' ],
		container_name    : args[ 'container_name' ],
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
		var hash = ptab.obj[ 'paginate_hash' ]( [ ptab.container_name, ptab.size + 1, start ] );
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
				if( thislc.access_test( thislc.app.account() ) ) {
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
					  if( thislc.access_test( thislc.app.account() ) ) {
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
	if( ! lc.access_test( lc.app.account() ) ) {
	    lc.make_login();
	}
 
	lc.on_logout_fun = args[ 'on_logout_function' ] || lc.make_login;
	lc.on_login_fun = args[ 'on_login_fun' ]  || lc.on_login;
	if( lc.access_test( lc.app.account() ) ) {
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

    check_edit:function( fld, checked_fun, unchecked_fun, extra_classes ) {
	return function( item, is_prep ) {
	    var div_id = 'ed_' + item.id + '_' + fld;
	    if( is_prep ) {
		extra_classes = extra_classes ? extra_classes : [];
		return '<input type="checkbox" id="' + div_id + '" ' +
		    ( 1 * item.get( fld ) == 1 ? ' checked' : '' ) +
		    ' class="' + extra_classes.join(' ') + '">';
	    } else {
		$( '#' + div_id ).click( function() {
		    if( $( '#' + div_id ).is( ':checked' ) ) {
			if( checked_fun ) {
			    checked_fun(item);
			} else {

			    item.set( fld, 1 );
			}
		    } else {
			if( unchecked_fun ) {
			    unchecked_fun(item);
			} else {
			    item.set( fld, 0 );
			}
		    }
		} );
	    }
	};
    },

    template_edit:function( template_name, extra_classes, on_edit_f ) {
	return function( item, is_prep ) {
	    var tmplt = item.get( template_name );
	    if( ! tmplt ) {
		tmplt = $.yote.fetch_root().new_template();
	    }
	    if( is_prep ) {
		return $.yote.util.prep_edit( tmplt, 'text', extra_classes );
	    } else {
		$.yote.util.implement_edit( tmplt, 'text', on_edit_f );
	    }
	};
    },

    col_edit:function( fld, extra_classes, on_edit_f ) {
	return function( item, is_prep ) {
	    if( is_prep ) {
		return $.yote.util.prep_edit( item, fld, extra_classes );
	    } else {
		$.yote.util.implement_edit( item, fld, on_edit_f );
	    }
	};
    }, //col_edit

    cols_edit:function( flds, titles, extra_classes ) {
	var use_titles = titles || flds;
	return function( item, is_prep ) {
	    if( is_prep ) {
		var tab = $.yote.util.make_table();
		for( var i=0; i<flds.length; i++ ) {
		    tab.add_param_row( [ use_titles[ i ], $.yote.util.prep_edit( item, flds[i], extra_classes ) ] );
		}
		return tab.get_html();
	    } else {
		for( var i=0; i<flds.length; i++ ) {
		    $.yote.util.implement_edit( item, flds[i] );
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
	    'edit_requires','field',
	    'container_name', 'paginate_type', 'paginate_order', 'is_admin',
	    'plimit',
	    'suppress_table', 'title', 'description', 'prefix_classname',
	    'include_remove', 'remove_button_text', 'remove_column_text',

	    'new_attachpoint',
	    'new_button', 'new_title', 'new_description',

	    'column_headers', 'columns', 'new_columns', 'new_columns_required',
	    'new_required_by_index', 'new_column_titles', 'new_column_placeholders',
	    'new_requires', 'new_object_type',

	    'item',
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

		// reference
		else if( attr_val.charAt(0) == '$' ) {
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
	    if( args[ 'item' ] ) {
		$.yote.util.yote_panel( args );
	    }
	    else {
		$( args[ 'attachpoint' ] ).empty();
	    }
	}
	return;
    }, //init_el

    refresh_ui:function() {
	$( '.control_table,.yote_panel' ).each( function() {
	    $( this ).attr( 'has_init', 'false' );
	} );
	$.yote.util.init_ui();
    }, //refresh_ui
    
    init_ui:function() {
	var may_need_init = false;
	$( '.control_table,.yote_panel' ).each( function() {
	    var el = $( this );
	    // init can be called multiple times, but only
	    // inits on the first time

	    if( el.attr( 'has_init' ) == 'true' ) {
		return;
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

	if( field ) {
	    var use_html = false;
	    if( field.charAt(0) == '#' ) {
		use_html = true;
		field = field.substring(1);
	    }
	    if( args[ 'edit_requires' ] == 'none' || 
		( args[ 'edit_requires' ] == 'root'  && $.yote.is_root() ) || 
		( args[ 'edit_requires' ] == 'login' && $.yote.is_logged_in() ) ) {
		$( args[ 'attachpoint' ] ).empty().append(
		    $.yote.util.prep_edit( item, field, '', use_html )
		);
		$.yote.util.implement_edit( item, field );
	    }
	    else {
		if( use_html ) {
		    $( args[ 'attachpoint' ] ).empty().append(
			item.get( field )
		    );
		}
		else {
		    $( args[ 'attachpoint' ] ).text(
			item.get( field )
		    );
		}
	    }
	}
    },


    // this tool is to create a table where the rows correspond to a list in a target
    // objects and the end user can add or remove the rows, or manipulate them
    control_table:function( args ) {
	var ct = {
	    ct_id		: this.next_id(),                         // a unique ID to make sure the namespace here is unique
	    terms		: [],                                     // used by search to keep track if search should be invoked or not

	    /* PAGINATION */
	    start		: 0,                                      // pagination start
	    plimit		: args[ 'plimit' ],                       // pagination limit
	    show_count          : typeof args[ 'show_count' ] === 'undefined' ? true : args[ 'show_count' ],

	    search_fun		: args[ 'search_function' ],              // optional alternate search function. Uses the default. which is search_list
	    search_on		: args[ 'search_on' ],                    // List of what search fields to use for the item. This may or may not be used by the item's search function depending on how it is defined. If this is included, search will be activated.

	    /* DATA */
	    item		: args[ 'item' ],                          // item that contains the list
	    container_name      : args[ 'container_name' ],                     //   name of list attached to item
	    paginate_type	: args[ 'paginate_type' ] || 'list',       //   list or hash
	    paginate_order	: args[ 'paginate_order' ] || 'forward',   //   forward or backwards
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
	    after_new_fun	: args[ 'after_new_function' ],                           // function this is run after new_function and takes a single argument : the newly created thing.
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
		this.terms = [];
		this.refresh();
	    },

	    refresh : function() {
		var me = this;


		var paginate_function;

		(function(it) {
		    if( it.search_on && it.terms.length > 0 ) {
			paginate_function = function() {
			    if( it.search_fun ) {
				// TODO : make these into an argument list
				return it.search_fun( [ it.container_name, it.search_on, it.terms, it.plimit + 1, it.start ] );
			    } else {
				return it.item.paginate( { name : it.container_name, limit : it.plimit + 1, skip : it.start,
							   search_fields : it.search_on, search_terms : it.terms,
							   return_hash : it.paginate_type != 'list' ? 1 : 0,
							   reverse : it.paginate_order != 'forward' ? 1 : 0 } );
			    }
			}
		    }
		    else {
			paginate_function = function() {
			    return it.item.paginate( { name : it.container_name, limit : it.plimit + 1, return_hash : it.paginate_type != 'list' ? 1 : 0, skip : it.start, reverse : it.paginate_order != 'forward' ? 1 : 0 } );
			}
		    }
		} )( me );


		// calculated
		var count          = me.item.count( me.container_name );
		me.plimit          = me.plimit ? me.plimit : count;
		var buf = me.title ? '<span class="' + me._classes( '_title' ) + '">' + me.title + '</span>' : '';
		buf    += me.description ? '<span class="' + me._classes( '_description' ) + '">' + me.description + '</span>' : '';

		if( me.search_on ) {
		    buf += '<div id="_search_div_' + me.ct_id + '" class="' + me._classes( '_search_div' ) + '">Search <input class="' + me._classes( '_search_input' ) + '"  type="text" id="_search_txt_' + me.ct_id + '" value="' + me.terms.join(' ') + '"> ' +
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
				tbl.add_row( [ me.new_column_titles[ i ], nc.render( id ) ], me._classes_array( 'new_item_row' ), me._classes_array( 'new_item_cell' ) );
			    } else {
				if( me.new_column_titles[ i ] ) {
				    tbl.add_param_row( [ me.new_column_titles[ i ], '<INPUT TYPE="TEXT" ' + ( me.new_column_placeholders[i] ? ' placeholder="' + me.new_column_placeholders[i] + '"' : '') + ' class="' + me._classes( '_new_item_field' ) + '" id="' + id + '">' ], me._classes_array( 'new_item_row' ), me._classes_array( 'new_item_cell' ) );
				} else {
				    tbl.add_row( [ '<INPUT TYPE="TEXT" ' + ( me.new_column_placeholders[i] ? ' placeholder="' + me.new_column_placeholders[i] + '"' : '') + ' class="' + me._classes( '_new_item_field' ) + '" id="' + id + '">' ], me._classes_array( 'new_item_row' ), me._classes_array( 'new_item_cell' ) );
				}
			    }
			    txts.push( '#' + id );
			} //each new column
			bf += tbl.get_html();
			bf += '<BUTTON type="BUTTON" class="' + me.prefix_classname + '_new_item_btn _ct_new_item_btn" id="_new_' + me.ct_id + '_' + me.item.id + '_b">' + me.new_button + '</BUTTON>';
			$( me.new_attachpoint ).empty().append( bf );


			for( var i=0; i < me.new_columns.length; i++ ) {
			    var nc = me.new_columns[ i ];
			    if( typeof nc === 'object' && nc[ 'after_render' ] ) {
				nc.after_render( '_new_' + me.ct_id + '_' + me.item.id + '_' + nc.field );
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
				for( var i=0; i < it.new_columns.length; i++ ) {
				    var nc = it.new_columns[ i ];

				    var field = typeof nc === 'object' ? nc.field : nc;
				    var id = '_new_' + me.ct_id + '_' + me.item.id + '_' + field;
				    if( typeof nc === 'object' ) {
					nc.on_create( newitem, id );
				    }
				    else {
					var val = $( '#' + id  ).val();
					newitem.set( nc, val );
				    }
				} //each column
				it.item.add_to( { name : it.container_name, items : [ newitem ] } );
				if( it.after_new_fun ) {
				    it.after_new_fun( newitem );
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
			buf += '<BR>Showing ' + max + ' of ' + count + ' items<BR>';
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
		else {
		    for( var i = 0 ; i < max ; i++ ) {
			var item = items.get( i );
			var row = [];
			for( var j = 0 ; j < me.columns.length; j++ ) {
			    var ctype = typeof me.columns[ j ];
			    if( ctype == 'string' && me.columns[ j ].charAt(0) == '*' ) {
				me.columns[j ] = $.yote.util.col_edit( me.columns[j].substring(1) );
				ctype = 'function';
			    }
			    row.push( ctype == 'function' ?
				      me.columns[ j ]( item, true ) :
				      ctype == 'object' ?
				      me.columns[ j ][ 'render' ]( item, me.start + i )
				      : item.get( me.columns[ j ] )
				    );
			}
			if( me.include_remove && ! me.suppress_table ) {
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
		    buf += me.show_when_empty( me.terms );
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
		    var e = me.start + me.plimit;
		    if( e > count ) {
			e = count - me.plimit;
		    }
		    $( '#forward_' + me.ct_id + '_b' ).click(function() { me.start = e; me.refresh() } );
		    $( '#to_end_' + me.ct_id + '_b' ).click(function() { me.start = count - me.plimit; me.refresh(); } );
		}
		else {
		    $( '#to_end_' + me.ct_id + '_b' ).attr( 'disabled', 'disabled' );
		    $( '#forward_' + me.ct_id + '_b' ).attr( 'disabled', 'disabled' );
		}

		if( me.search_on ) {
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
				it.terms = $( srch_txt ).val().split( /[ ,;]+/ );
			    } else {
				it.terms = [];
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
		    me.after_render_when_empty( me.terms );
		}
	    } //refresh
	}; //define cgt
	ct.refresh();
	if( ct.after_load ) ct.after_load();

	return ct;
    } //control_table

}//$.yote.util
