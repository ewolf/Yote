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
    }, //format_date

    //
    // Makes sure all things that match the selector have the
    // same width.
    // 
    match_widths: function( selector, buff ) {
	var max_width = 0;
	$( selector ).each( function() {
	    var w = $( this ).width();
	    max_width = max_width > w ? max_width : w;
	} );
	if( buff > 0 ) max_width += buff;
	$( selector ).each( function() {
	    $( this ).width( max_width );
	} );
    }, //match_widths

    registered_items : {},

    registered_templates : {},
    
    template_lookup : {},

    after_render_functions : [],

    register_items:function( hashed_items ) {
	for( var key in hashed_items ) {
	     $.yote.util.registered_items[ key ] = hashed_items[ key ];
	}
    }, //register_items
    register_item:function( name, val ) {
	$.yote.util.registered_items[ name ] = val;
    }, //register_item
    unregister_item:function( name ) {
	delete $.yote.util.registered_items[ name ];
    }, //unregister_item
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
    }, //next_id

    implement_edit:function( item, field, on_edit_function, id, additional_classes ) {
	var id_root  = id || item.id + '_' + field;

	var editor = {
	    item  : item,
	    field : field,
	    on_edit_function : on_edit_function,
	    additional_classes : additional_classes ? additional_classes + '' : '',
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
		$.yote.util.implement_edit( me.item, me.field, me.on_edit_function, id_root, me.additional_classes );
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
						     'height:' + h + 'px;" class="in_edit_same ' + me.additional_classes + '" id="' + me.txt_id + '"></textarea><BR>' +
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
$( '#' + me.div_id ).empty().append( val );

		var val = item.get( field );
		if( val ) {
		    if( $( '#' + me.div_id ).attr( 'as_html' ) == 'true' ) {
			$( '#' + me.div_id ).empty().append( val );
		    } else {
			$( '#' + me.div_id ).empty().text( val );
		    }
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

    check_edit:function( fld, updated_fun, extra_classes ) {
	var chk_id = '__' + $.yote.util.next_id();
	return function( item, is_prep ) {
	    if( is_prep ) {
		extra_classes = extra_classes ? extra_classes : [];
		return '<input type="checkbox" id="' + chk_id + '" ' +
		    ( 1 * item.get( fld ) == 1 ? ' checked' : '' ) +
		    ' class="' + extra_classes.join(' ') + '">';
	    } else {
		$( '#' + chk_id ).click( function() {
		    var chked = $( '#' + chk_id ).is( ':checked' );
		    item.set( fld, chked ? 1 : 0 );
		    updated_fun( chked, item, fld );
		} );
	    }
	};
    }, //check_edit

    // makes a select that controls a field on an object that is also an object.
    select_obj_edit:function( fld, list_obj, list_item_field, after_change_fun ) {
	var sel_id = '__' + $.yote.util.next_id();
	return function( item, is_prep ) {
	    if( is_prep ) {
		return '<SELECT id="' + sel_id + '">' + list_obj.to_list().map(function(it,idx){if( typeof it !== 'object' ) return '<option value="' + it + '">' + it + '</option>'; return '<option ' + ( item.get(fld) && item.get(fld).id == it.id ? 'SELECTED ' : '' ) + ' value="'+idx+'">'+it.get(list_item_field)+'</option>'}).join('') + '</SELECT>';
	    }
	    else {
		$( '#' + sel_id ).change( function() {
		    item.set( fld, list_obj.get( $(this).val() * 1 ) );
		    if( after_change_fun ) after_change_fun(item,list_obj);
		} );
	    }
	};
    }, //select_obj_edit

    // makes a select that controls a text field on an object
    select_edit:function( fld, list_obj, after_change_fun ) {
	var sel_id = '__' + $.yote.util.next_id();
	return function( item, is_prep ) {
	    if( is_prep ) {
		return '<SELECT id="' + sel_id + '">' + list_obj.map(function(it,idx){return '<option ' + ( item.get(fld) && item.get(fld) == it ? 'SELECTED ' : '' ) + ' value="'+idx+'">'+it+'</option>'}).join('') + '</SELECT>';
	    }
	    else {
		$( '#' + sel_id ).change( function() {
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
	    'edit_requires','field','no_edit','after_edit_function','use_checkbox', 'use_select','use_select_obj','show','action',
	    'container_name', 'is_admin','sel_list','list_field','list_obj',
	    'item', 'parent', 'value','bare','checked','template_id', 'additional_classes', 'new_button'
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

	// if the control has a template id, then grab values from that stored template context.
	if( args[ 'template_id' ] ) {
	    var ctx = $.yote.util.template_context[ args.template_id ];
	    if( ctx ) {
		for( fld in ctx ) {
		    if( ! args[ fld ] ) { 
			args[ fld ] = ctx[ fld ];
		    }
		}
	    }
	}

	if( el.hasClass( 'yote_panel' ) ) {
	    if( args[ 'item' ] || args['show'] ) {
		$.yote.util.yote_panel( args );
	    }
	    else {
		$( args[ 'attachpoint' ] ).empty();
	    }
	} //yote_panel
	else if( el.hasClass( 'yote_button' ) ) {
	    if( args[ 'action' ] ) {
		if( ! args[ 'default_var' ] ) args[ 'default_var' ] = args[ 'item' ];
		if( ! args[ 'default_parent' ] ) args[ 'default_parent' ] = args[ 'parent' ];
//WOLF - here is here the args get introduced to the template id instance
		(function(a) {
		$( a[ 'attachpoint' ] ).click(function(){
		    if( a[ 'action' ].indexOf('__') == 0 && $.yote.util.intrinsic_functions[ a[ 'action' ].substring(2) ] ) {
			$.yote.util.intrinsic_functions[ a[ 'action' ].substring(2) ]( a );
		    }
		    else if( $.yote.util.functions[ a[ 'action' ] ] ) {
			$.yote.util.functions[ a[ 'action' ] ]( a )
		    } else if( typeof window[ a[ 'action' ] ] === 'function' ) {
			window[ a[ 'action' ] ]( a );
		    } else {
			console.log( "'" + a['action'] + "' not found for button." );
		    }
		} );
		} )( args );
	    } else {
		console.log( "No action found for button." );
	    }
	} //yote_button
	else if( el.hasClass( 'yote_action_link' ) ) {
	    if( args[ 'action' ] ) {
		if( ! args[ 'default_var' ] ) args[ 'default_var' ] = args[ 'item' ];
		if( ! args[ 'default_parent' ] ) args[ 'default_parent' ] = args[ 'parent' ];
		$( args[ 'attachpoint' ] ).click(function(ev){
		    ev.preventDefault();
		    if( $.yote.util.functions[ args[ 'action' ] ] ) {
			$.yote.util.functions[ args[ 'action' ] ]( args[ 'item' ], args[ 'parent' ] );
		    } else if( typeof window[ args[ 'action' ] ] === 'function' ) {
			window[ args[ 'action' ] ]( args );
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
	if( $.yote.util.refresh_flag ) return;
	if( $.yote.util.functions.refresh_all ) {
	    $.yote.util.refresh_flag = true;
	    $.yote.util.functions.refresh_all(sel);
	}
	$.yote.util._refresh_ui( sel );
	$.yote.util.refresh_flag = false;
    },

    _refresh_ui:function(sel) {
	$( sel || '.yote_panel,.yote_button,.yote_template' ).each( function() {
	    $( this ).attr( 'has_init', 'false' );
	} );
	$.yote.util.init_ui();
    }, //_refresh_ui

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
 	    var def_var    = $.yote.util.lookup_template_var( { target : $( this ).attr( 'default_variable' ) } );
	    var parent_var = el.attr( 'default_parent' );
	    var templ_name = el.attr( 'template' );
	    try { 
		el.empty().append( $.yote.util.fill_template( $.yote.util.context( {
		    template_name : templ_name,
		    default_var : def_var,
		    parent_var  : parent_var } ) ) );
	    } catch( Err ) {
		console.log( Err + ' for template ' + templ_name );
	    }
	} );

	$( '.yote_panel,.yote_button,.yote_action_link' ).each( function() {
	    var el = $( this );
	    // init can be called multiple times, but only
	    // inits on the first time
	    if( el.attr( 'has_init' ) == 'true' || el.attr( 'disabled' ) == 'true' ) {
		return;
	    }
	    if( ! el.attr( 'id' ) ) { //make sure there is an ID for this element so it can be identified to fill in to it.
		el.attr( 'id', '__CNTROL_ID_' + $.yote.util.next_id() );
	    }
	    el.attr( 'has_init', 'true' );
	    $.yote.util.init_el(el);
	    may_need_init = true;
	} ); //each div
	for( var i = 0 ; i <  $.yote.util.after_render_functions.length; i++ ) {
	    $.yote.util.after_render_functions[ i ]();
	}
	$.yote.util.after_render_functions = [];

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
	var additional_classes = args[ 'additional_classes' ] ? args[ 'additional_classes' ] + '' : '';
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
			$.yote.util.prep_edit( item, field, [ additional_classes ], use_html, id )
		    );
		    $.yote.util.implement_edit( item, field, aef, id, additional_classes );
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
		var chk_id = '__' + $.yote.util.next_id();
		$( args[ 'attachpoint' ] ).empty().append(
		    '<input type="checkbox" id="' + chk_id + '" ' + ( args[ 'checked' ] ? 'checked' : '' ) + '>'
		);
		var f = $.yote.util.functions[ args[ 'after_edit_function' ] ];
		if( f ) {
		    $( '#' + chk_id ).click( function() {
			var chked = $( '#' + chk_id ).is( ':checked' );
			f( chked, args[ 'item' ], args[ 'parent' ], args[ 'template_id' ], args[ 'hash_key_or_index' ] );
		    } );
		}
	    }
	}
    }, //yote_panel


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
  how is this bootstrapped?

  Editing templates as yote variables, too?

*/

    templates : {},
    functions : {},
    template_context : {},
    _new_with_same_permissions : function( args ) {
	if( args[ 'default_var' ] ) { 
	    var newv = args[ 'default_var' ].new_with_same_permissions();
	    if( newv ) {
		var newf = args[ 'new_fields' ] || {};
		for( var k in newf ) {
		    var f = $( '#' + newf[ k ] );
		    if( f ) {
			if( f.attr( 'type' ) == 'checkbox' ) {
			    newv.set( k, f.is( ':checked' ) ? 1 : 0 );
			} else {
			    newv.set( k, f.val() );
			}
		    }
		}
		return newv;
	    } 
	}
	return undefined;
    }, //_new_with_same_permissions
    intrinsic_functions : {
	new_with_same_permissions_to_container : function( args ) {
	    //default var is the host object of the container, field is the container name that is in the host object
	    if( args[ 'default_var' ] && args[ 'field' ] ) { 
		var newv = $.yote.util._new_with_same_permissions( args );
		if( newv ) {
		    if( args[ 'new_hashkey' ] ) {
			args[ 'default_var' ].hash( { key   : args[ 'new_hashkey' ],
						      name  : args[ 'field' ],
						      value : newv } );
		    }
		    else {
			args[ 'default_var' ].add_to( { name : args[ 'field' ], items : [ newv ] } );
		    }
		    $.yote.util.refresh_ui();
		}
	    }
	    console.log( 'warning : intrinsic new_with_same_permissions_to_container called without both default_var and field' );
	    return null;
	}, //new_with_same_permissions_to_container
	remove_from_list : function( args ) {
	    if( args[ 'default_parent' ] && args[ 'default_var' ] && args[ 'field' ] ) {
		args[ 'default_parent' ].remove_from( { name : args[ 'field' ], items : [ args[ 'default_var' ] ] } );
		var container = args[ 'default_parent' ].wrap_list( { collection_name : args[ 'field' ], wrap_key : $.yote.util.find_parent_template_name( args ) }, true );
		if( container && container.start > 0 ) {
		    container.start--;
		}
		$.yote.util.refresh_ui();
	    }
	}, //remove_from_list
    }, //intrinsic_functions

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
    }, //register_function
    
    register_functions:function( hash ) {
	var name, val;
	for( name in hash ) {
	    $.yote.util.register_function( name, hash[ name ] );
	}
    }, //register_function

    clone_template_args:function( args ) {
	if( ! args ) return {};
	// clone the template arg hash. This is implemented because there are some lists attached to the arguments
	// that should also be cloned.
	var clone = Object.clone( args );
	if( clone[ 'new_fields' ] ) clone.new_fields = Object.clone( args[ 'new_fields' ] );
	if( clone[ 'vars' ] ) clone.vars = Object.clone( args[ 'vars' ] );
	if( clone[ 'controls' ] ) clone.controls = Object.clone( args[ 'controls' ] );
	return clone;
    }, //clone_template_args

    find_parent_template_name:function( args ) {
	return $.yote.util.template_lookup[ args[ 'parent_template_id' ] ];
    }, //find_parent_template_name

    find_template_name:function( args ) {
	return $.yote.util.template_lookup[ args[ 'template_id' ] ];
    }, //find_template_name

    fill_template:function( params, old_context ) {
	/*
	  ENTRY POINT FOR APPLYING TEMPLATE.
	 */
	var template = $.yote.util.templates[ params[ 'template_name' ] ];
	if( ! template ) { return ''; }

        var args = $.yote.util.clone_template_args( params );
        args[ 'template' ] = template;
	args[ 'template_id' ] = $.yote.util.next_id();
	args[ 'parent_template_id' ] = old_context;
	$.yote.util.template_lookup[ args[ 'template_id' ] ] = args[ 'template_name' ];

	var oc = $.yote.util.template_context[ old_context ];
	if( oc ) {
	    $.yote.util.template_context[ args[ 'template_id' ] ] = $.yote.util.context( { 
		vars : oc[ 'vars' ] ? Object.clone( oc[ 'vars' ] ) : {},
		newfields : oc[ 'newfields' ] ? Object.clone( oc[ 'newfields' ] ) : {},
		controls : oc[ 'controls' ] ? Object.clone( oc[ 'controls' ] ) : {},
		functions : oc[ 'functions' ] ? Object.clone( oc[ 'functions' ] ) : {}
	    } );
	}
	else {
	    $.yote.util.template_context[ args[ 'template_id' ] ] = $.yote.util.context();
	}

	return $.yote.util.fill_template_text( args );
    }, //fill_template

    _template_parts:function( txt, sigil, template ) {
	var rev_sigil = sigil.split('').reverse().join('');
	var start = txt.indexOf( '<' + sigil );
	var end   = txt.indexOf( rev_sigil + '>' );
	if( end == -1 ) throw new Error( "Error, mismatched templates" );
	var len   = sigil.length + 1;

	// recalculate the start if need be...this chunk should not have two 
	// starts in a row..actally just reverse the string and find the 
	// first rev_sigel...so
	//   '<$$ <$$ foo bar $$>' ---> <$$ rab oof $$> $$>
	//                          end ^           ^ lenstring - indexof rev is start
	// however, the while loop will work as well
	
	while( txt.substring( start + len, end ).indexOf( '<' + sigil ) >= 0 ) {
	    start = txt.substring( start + len, end ).indexOf( '<' + sigil );
	}

	if( end < start ) {
	    console.log( "Template error for '"+template+"' : unable to find close of <" + sigil );
	    return;
	}
	return [ txt.substring( 0, start ),
		 txt.substring( start + len, end ).trim(),
		 txt.substring( end+len ) ];
    }, //_template_parts

    fill_template_text:function( params ) {
        var template = params[ 'template' ]
	var text_val = typeof template === 'function' ? template() : template;
	if( ! text_val ) return '';
	while( text_val.indexOf( '<???' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '???', template );
	    try { 
		var f = eval( '['+parts[1]+']');
		text_val = parts[ 0 ] + f[0]( params ) + parts[ 2 ];
	    }
	    catch( err ) {
		console.log( 'error in function ' + parts[1] + ' : ' + err);
		text_val = parts[ 0 ] + parts[ 2 ];
	    }
	}
	while( text_val.indexOf( '<$$$' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '$$$', template );
	    text_val = parts[ 0 ] + $.yote.util.register_template_value( parts[ 1 ], params ) + parts[ 2 ];
	}
	while( text_val.indexOf( '<??' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '??', template );
	    if( parts[1].match( /^\s*function[\( ]/ ) ) {
		try { 
		    var f = eval( '['+parts[1]+']');
		    text_val = parts[ 0 ] + f[0]( params ) + parts[ 2 ];
		}
		catch( err ) {
		    console.log( 'error in function ' + parts[1] + ' : ' + err);
		    text_val = parts[ 0 ] + parts[ 2 ];
		}
	    }
	    else {
		params[ 'function_name' ] = parts[ 1 ];
		text_val = parts[ 0 ] +
		    $.yote.util.run_template_function( params ) +
		    parts[ 2 ];
	    }
	} // ??>
	while( text_val.indexOf( '<$@' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '$@', template );
	    var args = $.yote.util.clone_template_args( params );
            args[ 'template_body' ] = parts[ 1 ];
	    text_val = parts[ 0 ] +
		$.yote.util.fill_template_container( args, false ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<$%' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '$%', template );
	    var args = $.yote.util.clone_template_args( params );
            args[ 'template_body' ] = parts[ 1 ];
	    text_val = parts[ 0 ] +
		$.yote.util.fill_template_container( args, true ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<@' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '@', template );
	    var args = $.yote.util.clone_template_args( params );
            args[ 'template_body' ] = parts[ 1 ];
	    text_val = parts[ 0 ] +
		$.yote.util.fill_template_container_rows( args, true ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<%' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '%', template );
	    var args = $.yote.util.clone_template_args( params );
            args[ 'template_body' ] = parts[ 1 ];
	    text_val = parts[ 0 ] +
		$.yote.util.fill_template_container_rows( args, false ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<$$' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '$$', template );
	    var args = $.yote.util.clone_template_args( params );
	    var funparts = parts[1].match( /^\s*(\S+)(\s+[\s\S]*)?\s*$/ );
	    if( funparts ) {
		if( funparts.length == 3 && funparts[2] ) {
		    args[ 'extra' ] = funparts[2].trim();
		}
		args[ 'template_name' ] = funparts[ 1 ];
		text_val = parts[ 0 ] +
		    $.yote.util.fill_template( args, args[ 'template_id' ] ) +
		    parts[ 2 ];
	    } else {
		text_val = parts[ 0 ] + parts[ 2 ];
		console.log( 'Warning .. empty template given' );
	    }
	}
	while( text_val.indexOf( '<$' ) > -1 ) {
	    var parts = $.yote.util._template_parts( text_val, '$', template );
	    var args = $.yote.util.clone_template_args( params );
            args[ 'template_body' ] = parts[ 1 ];
	    text_val = parts[ 0 ] +
		$.yote.util.fill_template_variable( args ) +
		parts[ 2 ];
	}
	while( text_val.indexOf( '<?' ) > -1 ) {

	    // functions to be run after rendering is done
	    var parts = $.yote.util._template_parts( text_val, '?', template );
	    var args = $.yote.util.clone_template_args( params );

	    (function(fn, arg ) {
		$.yote.util.after_render_functions.push( function() {
		    var f;
		    if( fn.match( /^\s*function[\( ]/ ) ) {
			try { 
			    f = eval( '['+fn+']')[ 0 ];
			}
			catch( err ) {
			    console.log( 'error in function ' + fn + ' : ' + err);
			}
		    }
		    else {
			f = $.yote.util.functions[ fn ];
		    }
		    if( f ) {
			f( arg );
		    } else {
			console.log( "Template in after render function. Function '" + fn + "' not found." );
		    }
		} );
	    } )( parts[ 1 ].trim(), args );
	    text_val = parts[ 0 ] + parts[ 2 ];
	}
	return text_val;
    }, //fill_template_text

    run_template_function:function( params ) {
        if( params.function_name ) {
	    var f = $.yote.util.template_context[ params[ 'template_id' ] ][ 'functions' ][ params.function_name ] || $.yote.util.functions[ params.function_name ];
	    if( f ) {
		var args = $.yote.util.clone_template_args( params );
                args[ 'template' ] = f( args );
	        return $.yote.util.fill_template_text( args );
            }
        }
	console.log( "Template error. Function '" + params[ 'function_name' ] + "' not found." );
	return '';
    }, //run_template_function

    register_template_value:function( text_val, params ) { //expects "_name_ (new(_hashkey)?)? <control>"

        // now about we change this around so that the following are legit :
        /*
          <$$$ var varname value $$$>
          <$$$ var varname othervar $$$>
          <$$$ aliaslist varname hostobj listname $$$>
          <$$$ aliashash varname hostobj hashname $$$>
          <$$$ control ctlname <..html control..> $$$>
	  <$$$ function foo(args) { ... } $$$>
	  <??? function(args) { ... } ???>
         */
	var parts = text_val.match( /^\s*(var|control|function|aliasresult|alias|aliaslist|aliashash|new|new_hashkey)\s+((\S+)([\s\S]*))?/i );
	if( parts ) {
            var cmd = parts[ 1 ];
            var varname = parts[ 3 ];
            if( cmd.toLowerCase() == 'var' ) {
		var args = $.yote.util.clone_template_args( params );
		args.template = parts[ 4 ]; // template may be misnamed, but it is what will be parsed and
		                                 // have a value extracted from it.
                var val = $.yote.util.fill_template_text( args ).trim();
                params.vars[ varname ] = val;
                $.yote.util.template_context[ params.template_id ].vars[ varname ] = val;
                return '';
            }
            else if( cmd.toLowerCase() == 'aliaslist' ) {
		var args = $.yote.util.clone_template_args( params );
		var listparts = parts[ 4 ].trim().split(/ +/);
		if( listparts.length == 2 ) {
		    args.target = listparts[ 0 ];
		    var host_obj = $.yote.util.lookup_template_var( args );
		    var container = host_obj.wrap_list( { collection_name : listparts[ 1 ],
							  wrap_key : args.template_id }, false );
		    params.vars[ varname ] = container;
                    $.yote.util.template_context[ params.template_id ][ 'vars' ][ varname ] = val;
		}
                return '';
	    }
            else if( cmd.toLowerCase() == 'alias' ) {
		var args = $.yote.util.clone_template_args( params );
		var targ = $.yote.util.lookup_template_var( { target : parts[ 4 ].trim() } );
		params.vars[ varname ] = targ;
                $.yote.util.template_context[ params.template_id ][ 'vars' ][ varname ] = targ;
                return '';
	    }
            else if( cmd.toLowerCase() == 'aliasresult' ) {
		var args = $.yote.util.clone_template_args( params );
		var targ = $.yote.util.lookup_template_var( { target : parts[ 4 ].trim() } );
		var fun = eval( '[' +  targ + ']' )[0];
		params.vars[ varname ] = fun( args );
                return '';
	    }
            else if( cmd.toLowerCase() == 'function' ) {
		var funparts = text_val.match( /^\s*function\s+([^\(\s]+)([\s\S]*)/ );
		var funname = funparts[1];

		var fun = eval( '[function ' + funparts[2] + ']' )[0];

		$.yote.util.template_context[ params[ 'template_id' ] ][ 'functions' ][ funname ] = fun;
		return '';
	    }

            var control = cmd.toLowerCase() == 'new_hashkey' ? parts[ 2 ] : parts[ 4 ];
	    var ctrl_parts = /\*\<[\s\S]* id\s*=\s*['"]?(\S+)['"]? /.exec( control );
	    var ctrl_id;
	    var ctrl = control;
	    if( ctrl_parts ) {
		ctrl_id = ctrl_parts[ 1 ];
	    }
	    else {
		ctrl_id = '__' + $.yote.util.next_id();
		ctrl = ctrl.replace( /^\s*(<\s*[^\s\>]+)([ \>])/, '$1 id="' + ctrl_id + '" $2' );
	    }
	    ctrl_parts = /\*\<[\s\S]* template_id\s*=\s*['"]?\S+['"]? /.exec( control );
	    if( ctrl_parts ) {
		console.log( "CANNOT ASSIGN TEMPLATE ID TO '" + control + '"' );
		return control;
	    }
	    else {
		ctrl = ctrl.replace( /^\s*(<\s*[^\s\>]+)([ \>])/, '$1 template_id="' + params[ 'template_id' ]  + '" $2' );
	    }

            if( cmd.toLowerCase() == 'new_hashkey' ) {
                params[ 'new_hashkey' ] = ctrl_id;
	        $.yote.util.template_context[ params[ 'template_id' ] ][ 'new_hashkey' ] = ctrl_id;
            }
            else { // new or control
                var tvar =  cmd.toLowerCase() == 'control' ? 'controls' : 'new_fields';
		if( ! params[ tvar ] ) params[ tvar ] = {};
                params[ tvar ][ varname ] = '#' + ctrl_id;
                if( ! $.yote.util.template_context[ params[ 'template_id' ] ][ tvar ] ) $.yote.util.template_context[ params[ 'template_id' ] ][ tvar ] = {};
                $.yote.util.template_context[ params[ 'template_id' ] ][ tvar ][ varname ] = '#' + ctrl_id;
            }
            return ctrl;
        } //has parts
        return '';

    }, //register_template_value

    fill_template_container:function( params, is_hash ) {
	var parts = params[ 'template_body' ].split(/ +/);
	if( parts.length < 3 ) {
	    console.log( "Template error for parsing '"+ params[ 'template_body' ] +"' : not enough arguments " );	    
	    return;
	}
	var args = $.yote.util.clone_template_args( params );
        args[ 'target' ] = parts[ 1 ].trim();

	var main_template     = parts[ 0 ].trim(),
	    on_empty_template = parts.length == 4 ? parts[ 3 ].trim() : parts[ 0 ].trim(),
            host_obj          = $.yote.util.lookup_template_var( args ),
	    container_name    = parts[ 2 ].trim();
	if( typeof host_obj === 'object' && container_name ) {
	    var container = host_obj.wrap( { collection_name : container_name,
					     size : args[ 'size' ],
					     wrap_key : main_template,
					   }, is_hash );
	    console.log( [ "HOSTY", host_obj, container ] );
            args[ 'template_name' ] = container.full_size() == 0 ? on_empty_template : main_template;
	    args[ 'default_var' ] = container;
	    args[ 'container_name' ] = container_name;
	    return $.yote.util.fill_template( args, args.template_id );
	}
	return '';
    }, //fill_template_container

    fill_template_container_rows:function( args, is_list ) {
	var parts = args[ 'template_body' ].split(/ +/);
        var row_template = parts[ 0 ].trim();
	var default_var, pagination_size;
	if( parts.length > 3 ) {
	    pagination_size = parts[ 3 ].trim() || 1;
	    var host_obj = args.getvar( parts[ 1 ].trim() );
	    default_var = host_obj.wrap( { collection_name : parts[ 2 ].trim(),
					   size : args[ 'size' ],
					   wrap_key : args.template_name,
					 }, ! is_list );
	} 
	else {
            pagination_size = parts[ 1 ].trim() || 1;
            default_var = args[ 'default_var' ];
	}
	// assumes default var is a list
        default_var.page_size = 1*pagination_size;
	if( is_list && default_var && default_var[ 'to_list' ] ) {
            return default_var.to_list().map(function(it,idx){
		var rowargs = $.yote.util.clone_template_args( args );
		rowargs[ 'template_name' ] = row_template;
		rowargs[ 'default_var' ] = it;
		rowargs[ 'default_parent' ] = default_var;
		rowargs[ 'hash_key_or_index' ] = idx;
		
		return $.yote.util.fill_template( rowargs );
            } ).join('');
	}
        if( ! is_list && default_var && default_var[ 'to_hash' ] ) {
            var hash = default_var.to_hash();
            var keys = Object.keys( hash );
            keys.sort();
            if( default_var[ 'sort_reverse' ] ) keys.reverse();
            return keys.map(function(key,idx){
		var rowargs = $.yote.util.clone_template_args( args );
                rowargs[ 'template_name' ] = row_template;
                rowargs[ 'default_var' ] = hash[ key ];
		rowargs[ 'default_parent' ] = default_var;
                rowargs[ 'hash_key_or_index' ] = key;
		
		return $.yote.util.fill_template( rowargs );
            } ).join('');
	}
	console.log( "Template error for '"+row_template+"' : default_var passed in is not the correct container " );
	return '';
    }, //fill_template_container_rows

    context:function( h ) {
	h = h ? h : {};
	var ret = {
	    vars : h.vars || {},
	    newfields : h.newfields || {},
	    controls : h.controls || {},
	    functions : h.functions || {},
	    getvar: function( vname ) {
		if( vname == '_' ) return this.default_var;
		return this.vars[ vname ] || $.yote.util.registered_items[ vname ];
	    },
	    fun: function( fname ) {
		return this.functions[ fname ] || $.yote.util.functions[ fname ];
	    },
	};
	for( var key in h ) {
	    if( typeof ret[ key ] === 'undefined' ) {
		ret[ key ] = h[ key ];
	    }
	}
	return ret;
    },

    lookup_template_var:function( args ) {
	if( ! args[ 'target' ] ) return null;
        var tlist = args[ 'target' ].trim().split(/[\.]/);
	var subj = tlist[0];
	var subjobj;
	if( subj == '_acct_' )      subjobj = $.yote.fetch_account();
	else if( subj == '_root_' ) subjobj = $.yote.fetch_root();
	else if( subj == '_app_' ) subjobj = $.yote.default_app;
	else if( subj == '_id_' )   subjobj = args[ 'template_id' ];
	else if( subj == '_' )    subjobj = args[ 'default_var' ];
	else if( subj == '__' )   subjobj = args[ 'default_parent' ];
	else if( subj == '___' )   subjobj = args[ 'extra' ];
	else subjobj = $.yote.util.registered_items[ subj ];
	if( subjobj ) {
	    for( i=1; i<tlist.length; i++ ) {
		subjobj = subjobj.get( tlist[i] );
	    }
	    return subjobj;
	}
	return subj;
    }, //_template_var

    fill_template_variable:function( args ) {
        var varcmd = args[ 'template_body' ];
        var template_id = args[ 'template_id' ];
	var cmdl = varcmd.split(/ +/); //yikes, this split suxx.use regex
	var cmd  = cmdl[0].toLowerCase();
	var subj = cmdl[1];
	var fld  = cmdl[2];
	var hash_key_or_index = args[ 'hash_key_or_index' ];
	if( cmd == 'hash_key' || cmd == 'index' ) {
	    return hash_key_or_index;
	}
        args[ 'target' ] = subj;
        var default_var = args[ 'default_var' ];
        var default_parent = args[ 'default_parent' ];
	var subjobj = $.yote.util.lookup_template_var( args );
	if( cmd == 'edit' ) {
	    if( ! subjobj ) return '';
	    return '<span class="yote_panel" ' + (fld.charAt(0) == '#' ? ' as_html="true" ' : '' ) + ' after_edit_function="*function(){$.yote.util.refresh_ui();}" item="$$' + subjobj.id + '" field="' + fld + '" template_id="' + args[ 'template_id' ] + '" additional_classes="' + ( cmdl[3] || '' ) + '"></span>';
	}
	else if( cmd == 'show' ) {
	    if( ! subjobj ) return '';
	    return '<span class="yote_panel" no_edit="true" ' + (fld.charAt(0) == '#' ? ' as_html="true" ' : '' ) + ' item="$$' + subjobj.id + '" field="' + fld + '" template_id="' + args[ 'template_id' ] + '"></span>';
	}
	else if( cmd == 'checkbox' ) {
	    if( ! subjobj ) return '';
	    return '<span class="yote_panel" use_checkbox="true" after_edit_function="*function(){$.yote.util.refresh_ui();}" item="$$' + subjobj.id + '" field="' + fld + '" template_id="' + args[ 'template_id' ] + '"></span>';
	}
	else if( cmd == 'switch' ) {
	    var oid = default_var ? default_var.id : 'undefined';
	    var poid = default_parent ? default_parent.id : 'undefined';
	    return '<span class="yote_panel" use_checkbox="true" bare="true" after_edit_function="' + subj + '" item="$$' + oid + '" parent="$$' + poid + '" template_id="' + template_id + '" hash_key_or_index="' + hash_key_or_index +'" ' + ( default_var && default_var.get( fld ) && default_var.get( fld ) != '0' ? ' checked="checked"' : '' ) + '></span>';
	}
	else if( cmd == 'select' ) {
	    if( ! subjobj ) return '';
	    parts = /^\s*\S+\s+\S+\s+\S+\s+([\s\S]*)/.exec( varcmd );
	    listblock = parts[ 1 ];
	    return '<span class="yote_panel" use_select="true" sel_list="' + listblock + '" after_edit_function="*function(){$.yote.util.refresh_ui();}" item="$$' + subjobj.id + '" field="' + fld + '" template_id="' + args[ 'template_id' ] + '"></span>';
	}
	else if( cmd == 'selectobj' ) {
            args[ 'target' ] = cmdl[3].trim();
	    var lst = $.yote.util.lookup_template_var( args );
	    if( lst ) {
		if( ! subjobj ) return '';
		return '<span class="yote_panel" use_select_obj="true" list_field="' + cmdl[4].trim() + '" list_obj="$$' + lst.id + '" after_edit_function="*function(){$.yote.util.refresh_ui();}" item="$$' + subjobj.id + '" field="' + fld + '" template_id="' + args[ 'template_id' ] + '"></span>';
	    }
	    console.log( "Could not find '" + cmdl[3] + "'" );
	    return '';
	}
	else if( cmd == 'button' ) {
	    parts = /^\s*(\S+)\s+(\S+)\s*([\s\S]*)/.exec( varcmd );
	    var item   = default_var;
	    var parent = default_parent;
	    var txt = parts ? parts[3].trim() : '';
	    return '<button type="BUTTON" ' + ( args[ 'container_name' ] ? 'container_name="' + args[ 'container_name' ] + '"'  : '' ) + ' ' + ( item ? ' item="$$' + item.id + '"' : '' ) +  ( parent ? ' parent="$$' + parent.id + '"' : '' ) + ' class="yote_button" action="' + subj.trim() +'" template_id="' + args[ 'template_id' ] + '">' + txt + '</button>';
	}
	else if( cmd == 'action_link' ) {
	    parts = /^\s*\S+\s+\S+\s*([\s\S]*)/.exec( varcmd );
	    var item   = default_var;
	    var parent = default_parent;
	    txt = parts ? parts[1].trim() : '';
	    return '<a href="#" ' + ( item ? ' item="$$' + item.id + '"' : '' ) +  ( parent ? ' parent="$$' + parent.id + '"' : '' ) + ' class="yote_action_link" action="' + subj.trim() +'" template_id="' + args[ 'template_id' ] + '">' + txt + '</a>';
	}
	else if( cmd == 'newbutton' ) {
	    parts = /^\s*\S+\s+\S+\s+\S+\s*([\s\S]*)/.exec( varcmd );
	    var subjobj = $.yote.util.lookup_template_var( args );
	    txt = parts ? parts[1].trim() : 'New';
	    return '<button type="BUTTON" item="$$' + subjobj.id + '" field="'+fld+'" class="yote_button" action="__new_with_same_permissions_to_container" template_id="' + args[ 'template_id' ] + '">' + txt + '</button>';
	}
	else if( cmd == 'list_remove_button' ) {
	    parts = /^\s*\S+\s+\S+\s+\S+\s*([\s\S]*)/.exec( varcmd );
	    var subjobj = $.yote.util.lookup_template_var( args );
	    txt = parts && parts[1] ? parts[1].trim() : 'Delete';
	    var parent = default_parent;
	    return '<button type="BUTTON" parent="$$' + parent.id + '" item="$$' + subjobj.id + '" field="'+fld+'" class="yote_button" action="__remove_from_list" template_id="' + args[ 'template_id' ] + '">' + txt + '</button>';
	}
	else if( cmd == 'show_or_edit' ) {
	    if( ! subjobj ) return '';
	    if( $.yote.is_root() ) {
		return '<span class="yote_panel" ' + (fld.charAt(0) == '#' ? ' as_html="true" ' : '' ) + ' after_edit_function="*function(){$.yote.util.refresh_ui();}" item="$$' + subjobj.id + '" field="' + fld + '" template_id="' + args[ 'template_id' ] + '"></span>';
	    }
	    else {
		return '<span class="yote_panel" no_edit="true" ' + (fld.charAt(0) == '#' ? ' as_html="true" ' : '' ) + ' item="$$' + subjobj.id + '" field="' + fld + '" template_id="' + args[ 'template_id' ] + '"></span>';
	    }
	}
	else if( cmd == 'val' ) {
	    var find_def = /^\s*\S+\s+\S+\s*([\s\S]*)/.exec( varcmd );
	    var def_val = find_def.length == 2 ? find_def[ 1 ] : '';
	    var tlist = subj.split(/[\.]/); 
	    var stored = args.getvar( tlist[0] ) || def_val;
	    if( tlist.length > 1 && typeof stored === 'object' ) {
		for( var i=1; i<tlist.length; i++ ) {
		    stored = stored.get( tlist[i] )
		}
	    }
	    return stored;
	}
	console.log( "template variable command '" + varcmd + '" not understood' );
	return varcmd;
    }, //fill_template_variable

/*
  Template sigils :
     <$$ template name $$>  <--- fills with template
     <$                 $>  <--- fills with variable
     <$% template empty_template registered_host_object hashname_in_host_object %>  <--- fills with template
     <$@ template empty_template registered_host_object listname_in_host_object @>  <--- fills with template

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
      * newbutton object_holding_container container_name button text
      * list_remove_button
      * show_or_edit item field ( if logged in user is root, do edit, otherwise just show )
      * val variablename 
      * radio   field ( like select with choose 1 ... implement at some point )


  ( default var as _ , parent as __  )


     <@ templatename list @>
     <@ templatename obj field @>
     <? command ?>   run the restigered function and include its text result in the html
     <?? after_template_renders_command arbitrary_args_as_a_single_string ??>  runs after the template this is in has been rendered.
   Applies the template to each item in the list, concatinating the results together.



*/

}//$.yote.util
