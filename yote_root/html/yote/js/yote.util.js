/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Version 0.027
 */
if( ! $.yote ) { $.yote = {}; }
$.yote.util = {

    // general useful utility functions go here.

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

    button_actions:function( args ) {
	var cue = {};
	if( args.cleanup_exempt ) {
	    for( var i=0; i < args.cleanup_exempt.length; i++ ) {
		cue[ args.cleanup_exempt[ i ] ] = true;
	    }
	}
	var ba = {
	    but         : args.button,
	    action      : args.action || function(){},
	    on_escape   : args.on_escape || function(){},
	    texts       : args.texts || [],
	    t_values    : args.texts.map( function(it,idx){ return $( it ).val(); } ),
	    req_texts   : args.required,
	    req_indexes : args.required_by_index,
	    req_fun     : args.required_by_function,
	    exempt      : cue,
	    extra_check : args.extra_check || function() { return true; },

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

}//$.yote.util
