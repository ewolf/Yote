/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Version 0.2
 */
// Production steps of ECMA-262, Edition 5, 15.4.4.19
// Reference: http://es5.github.com/#x15.4.4.19
if (!Array.prototype.map) {
    Array.prototype.map = function(callback, thisArg) {

	var T, A, k;

	if (this == null) {
	    throw new TypeError(" this is null or not defined");
	}

	// 1. Let O be the result of calling ToObject passing the |this| value as the argument.
	var O = Object(this);

	// 2. Let lenValue be the result of calling the Get internal method of O with the argument "length".
	// 3. Let len be ToUint32(lenValue).
	var len = O.length >>> 0;

	// 4. If IsCallable(callback) is false, throw a TypeError exception.
	// See: http://es5.github.com/#x9.11
	if ({}.toString.call(callback) != "[object Function]") {
	    throw new TypeError(callback + " is not a function");
	}

	// 5. If thisArg was supplied, let T be thisArg; else let T be undefined.
	if (thisArg) {
	    T = thisArg;
	}

	// 6. Let A be a new array created as if by the expression new Array(len) where Array is
	// the standard built-in constructor with that name and len is the value of len.
	A = new Array(len);

	// 7. Let k be 0
	k = 0;

	// 8. Repeat, while k < len
	while(k < len) {

	    var kValue, mappedValue;

	    // a. Let Pk be ToString(k).
	    //   This is implicit for LHS operands of the in operator
	    // b. Let kPresent be the result of calling the HasProperty internal method of O with argument Pk.
	    //   This step can be combined with c
	    // c. If kPresent is true, then
	    if (k in O) {

		// i. Let kValue be the result of calling the Get internal method of O with argument Pk.
		kValue = O[ k ];

		// ii. Let mappedValue be the result of calling the Call internal method of callback
		// with T as the this value and argument list containing kValue, k, and O.
		mappedValue = callback.call(T, kValue, k, O);

		// iii. Call the DefineOwnProperty internal method of A with arguments
		// Pk, Property Descriptor {Value: mappedValue, : true, Enumerable: true, Configurable: true},
		// and false.

		// In browsers that support Object.defineProperty, use the following:
		// Object.defineProperty(A, Pk, { value: mappedValue, writable: true, enumerable: true, configurable: true });

		// For best browser support, use the following:
		A[ k ] = mappedValue;
	    }
	    // d. Increase k by 1.
	    k++;
	}

	// 9. return A
	return A;
    };
} //map definition

if( ! Object.size ) {
    Object.size = function(obj) {
	var size = 0, key;
	for (key in obj) {
            if (obj.hasOwnProperty(key)) size++;
	}
	return size;
    };
}
if( ! Object.keys ) {
    Object.keys = function( t ) {
    	var k = []
	for( var key in t ) {
	    k.push( key );
	}
	return k;
    }
}


/*
  Upon script load, find the port that the script came from, if any.
 */
var scripts = document.getElementsByTagName('script');
var index = scripts.length - 1;
var myScriptUrl = scripts[index].src;
var ma = myScriptUrl.match( /^((https?:\/\/)?[^\/]+(:(\d+))?)\// );
var yote_scr_url = ma && ma.length > 1 ? ma[ 1 ] : '';
$.yote = {
    url:yote_scr_url,
    guest_token:0,
    token:0,
    port:null,
    err:null,
    objs:{},
    apps:{},
    debug:false,
    app:null,
    root:null,

    init:function() {
        var t = $.cookie('yoken');
	$.yote.token = t || 0;
	
	var root;
	if( ! $.yote.init_precache( root ) ) {
	    root = this.fetch_root();
	    $.yote.guest_token = root.guest_token();
	} else {
	    root = this.fetch_root();
	}	    

        if( typeof t === 'string' ) {
            var ret = root.token_login( $.yote.token );
	    if( typeof ret === 'object' ) {
		$.yote.token     = t;
		this.login_obj = ret;
	    }
        }

	return ret;
    }, //init

    init_precache:function( root ) {
	var precache = window['yote_precache'];
	if( ! precache ) return false;
	$.yote.guest_token = precache[ 'gt' ];
	$.yote.token = precache[ 't' ];
	var app_id = precache[ 'a' ];
	var precache_data = precache[ 'r' ];
	var appname = precache[ 'an' ];
	var app_data = precache[ 'ap' ];
	var acct_data = precache[ 'ac' ];
	var login_data = precache[ 'lo' ];
	if( appname && app_data ) { 
	    $.yote.objs['root'] = $.yote._create_obj( precache[ 'ro' ] );
	    var app = $.yote._create_obj( app_data, app_id );
	    app.__app_id = app_id;
	    $.yote.apps[ appname ] = app;
	    $.yote.app = app;
	    if( login_data ) {
		$.yote.login_obj = $.yote._create_obj( login_data );
	    }
	    if( acct_data ) {
		$.yote.acct_obj = $.yote._create_obj( acct_data, app_id );
	    }
	    resp = $.yote._create_obj( precache_data, app_id );
	    return true;
	}
	return false;
    },

    fetch_account:function() {
	if( this.app ) {
	    if( ! this.acct_obj ) {
		this.acct_obj = this.app.account();
	    }
	    return this.acct_obj;
	}
	return undefined;
    },

    fetch_app:function(appname,passhandler,failhandler) {
	if( $.yote.apps[ appname ] ) return $.yote.apps[ appname ];
	var root = this.fetch_root();
	if( typeof root === 'object' ) {
	    var ret = root.fetch_app_by_class( appname );
	    ret._app_id = ret.id;
	    this.app = ret;
	    $.yote.apps[ appname ] = ret;
	    return ret;
	} else if( typeof failhanlder === 'function' ) {
	    failhandler('lost connection to yote server');
	} else {
	    _error('lost connection to yote server');
	}
    }, //fetch_app

    fetch_root:function() {
	var r = this.objs['root'];
	if( ! r ) {
	    r = this.message( {
		async:false,
		cmd:'fetch_root',
		wait:true
	    } );
	    this.objs['root'] = r;
	    this.root = r;
	}
	return r;
    }, //fetch_root

    get_by_id:function( id ) {
	return $.yote.objs[id+''] || $.yote.fetch_root().fetch(id).get(0);
    },

    is_root:function() {
	return this.is_logged_in() && 1*this.get_login().is_root();
    },

    get_login:function() {
	return this.login_obj;
    }, //get_login

    is_logged_in:function() {
	return typeof this.login_obj === 'object';
    }, //is_logged_in

    login:function( handle, password, passhandler, failhandler ) {
	var root = this.fetch_root();
	if( typeof root === 'object' ) {
	    root.login( { h:handle, p:password },
			function(res) {
			    $.yote.token = res.get( 't' ) || 0;
			    $.yote.login_obj = res.get( 'l' );
			    $.cookie( 'yoken', $.yote.token, { path : '/' } );
			    if( typeof passhandler === 'function' ) {
				passhandler(res);
			    }
			},
			failhandler );
	    return $.yote.login_obj;
	} else if( typeof failhanlder === 'function' ) {
	    failhandler('lost connection to yote server');
	} else {
	    _error('lost connection to yote server');
	}
    }, //login

    logout:function() {
	$.yote.fetch_root().logout();
	$.yote.login_obj = undefined;
	$.yote.acct_obj = undefined;
	$.yote.token = 0;
	$.yote._dump_cache();
	$.cookie( 'yoken', '', { path : '/' } );
	if( $.yote.util ) {
	    $.yote.util.registered_items = {};
	}
    }, //logout

    /* general functions */
    message:function( params ) {
        var root   = this;
        var data   = root._translate_data( params.data || {} );
        var async  = params.async == true ? 1 : 0;
	var wait   = params.wait  == true ? 1 : 0;
        var url    = params.url;
        var app_id = params.app_id || '';
        var cmd    = params.cmd;
        var obj_id = params.obj_id || ''; //id to act on

	root.upload_count = 0;

	if( ! app_id ) app_id = 0;
	if( ! obj_id ) obj_id = 0;

        var url = $.yote.url + '/_/' + app_id + '/' + obj_id + '/' + cmd;

	var uploads = root._functions_in( data );
	if( uploads.length > 0 ) {
	    return root.upload_message( params, uploads );
	}
        if( async == 0 ) {
            root._disable();
        }
	var encoded_data = $.base64.encode( JSON.stringify( { d : data } ) );
        var get_data = $.yote.token + "/" + $.yote.guest_token + "/" + wait;
	var resp;

        if( $.yote.debug == true ) {
	    console.log("\noutgoing " + url + '-------------------------' );
	    console.log( data );
//	    console.log( JSON.stringify( {d:data} ) );
	}

	$.ajax( {
	    async:async,
	    cache: false,
	    contentType: "application/json; charset=utf-8",
	    data : encoded_data,
	    dataFilter:function(a,b) {
		if( $.yote.debug == true ) {
		    console.log('incoming '); console.log( a );
		}
		return a;
	    },
	    error:function(a,b,c) { root._error(a); },
	    success:function( data ) {
                if( typeof data !== 'undefined' ) {
		    resp = ''; //for returning synchronous

		    //dirty objects that may need a refresh
		    if( typeof data.d === 'object' ) {
			for( var oid in data.d ) {
			    if( root._is_in_cache( oid ) ) {
				var cached = root.objs[ oid + '' ];
				for( fld in cached._d ) {
				    //take off old getters/setters
				    delete cached['get_'+fld];
				}
				cached._d = data.d[ oid ];

				for( fld in cached._d ) {
				    //add new getters/setters
				    cached['get_'+fld] = (function(fl) { return function() { return this.get(fl) } } )(fld);
				}
			    }
			} //each dirty
		    } //if dirty

		    if( typeof data.err === 'undefined' ) {
			if( typeof data.r === 'object' ) {
			    resp = root._create_obj( data.r, app_id );
		            if( typeof params.passhandler === 'function' ) {
				params.passhandler( resp );
			    }
			} else if( typeof data.r === 'undefined' ) {
		            if( typeof params.passhandler === 'function' ) {
				params.passhandler();
			    }
			} else {
			    resp = data.r.substring( 1 );
		            if( typeof params.passhandler === 'function' ) {
				params.passhandler( resp );
			    }
		        }
		    } else if( typeof params.failhandler === 'function' ) {
		        params.failhandler(data.err);
                    } //error case. no handler defined
                } else {
                    console.log( "Success reported but no response data received" );
                }
	    },
	    type:'POST',
	    url:url + '/' + get_data
	} );
        if( ! async ) {
            root._reenable();
            return resp;
        }
    }, //message

    /* the upload function takes a selector returns a function that sets the name of the selector to a particular value,
       which corresponds to the parameter name in the inputs.
       For example some_yote_obj->do_something( { a : 'a data', file_up = upload( '#myfileuploader' ) } )
    */
    upload:function( selector_id ) {
	var uctxt = 'u' + this.upload_count++;
	$( selector_id ).attr( 'name', uctxt );
	return (function(uct, sel_id) {
	    return function( return_selector_id ) { //if given no arguments, just returns the name given to the file input control
		if( return_selector_id ) return sel_id;
		return uctxt;
	    };
	} )( uctxt, selector_id );
    }, //upload

    /* Should have a upload_multiple. This would pass the files as filename -> data pairs, and include a filenames list */

    /*
      This is called automatically by message if there is an upload involved. It is not meant to be invoked directly.
     */
    upload_message:function( params, uploads ) {


	// for multiple, upload the files in order, then get the filehelper objs as callbacks and then make the call

        var root   = this;
        var data   = root._translate_data( params.data || {}, true );
	var wait   = params.wait  == true ? 1 : 0;
        var url    = params.url;
        var app_id = params.app_id || '';
        var cmd    = params.cmd;
        var obj_id = params.obj_id || ''; //id to act on

        var url = $.yote.url + '/_u/' + app_id + '/' + obj_id + '/' + cmd;

	root.iframe_count++;
	var iframe_name = 'yote_upload_' + root.iframe_count;
	var form_id = 'yote_upload_form_' + root.iframe_count;
	var iframe = $( '<iframe id="' + iframe_name + '" name="' + iframe_name + '" style="position;absolute;top:-9999px;display:none" /> ').appendTo( 'body' );
	var form = '<form id="' + form_id + '" target="' + iframe_name + '" method="post" enctype="multipart/form-data" />';
	var upload_selector_ids = uploads.map( function( x ) { return x(true) } );
	var cb_list = [];
	$( upload_selector_ids.join(',') ).each(
	    function( idx, domEl ) {
		$( this ).prop( 'disabled', false );
		cb_list.push(  $( 'input:checkbox', this ) );
	    }
	);
	if( $.yote.debug == true ) {
	    console.log("\noutgoing " + url + '-------------------------' );
	    console.log( data );
	}

	var form_sel = $( upload_selector_ids.join(',') ).wrapAll( form ).parent('form').attr('action',url);
	$( '#' + form_id ).append( '<input type=hidden name=d value="' + $.base64.encode(JSON.stringify( {d:data} ) ) + '">');
	$( '#' + form_id ).append( '<input type=hidden name=t value="' + $.yote.token + '">');
	$( '#' + form_id ).append( '<input type=hidden name=gt value="' + $.yote.guest_token + '">');
	$( '#' + form_id ).append( '<input type=hidden name=w value="' + wait + '">');

	for( var i=0; i<cb_list.length; i++ ) {
	    cb_list[ i ].removeAttr('checked');
	    cb_list[ i ].attr('checked', true);
	}
	var resp;

	var xx = form_sel.submit(function() {
	    iframe.load(function() {
		var contents = $(this).contents().get(0).body.innerHTML;
		while( contents.match( /^\s*</ ) ) {
		    contents = contents.replace( /^\s*<\/?[^\>]*>/, '' );
		    contents = contents.replace( /<\/?[^\>]*>\s*$/, '' );
		}
		$( '#' + iframe_name ).remove();
		try {
		    resp = JSON.parse( contents );
		    if( $.yote.debug == true ) {
			console.log('incoming '); console.log( resp );
		    }
		    
                    if( typeof resp !== 'undefined' ) {
			if( typeof resp.err === 'undefined' ) {
			    //dirty objects that may need a refresh
			    if( typeof resp.d === 'object' ) {
				for( var oid in resp.d ) {
				    if( root._is_in_cache( oid ) ) {
					var cached = root.objs[ oid + '' ];
					for( fld in cached._d ) {
					    //take off old getters/setters
					    delete cached['get_'+fld];
					}
					cached._d = resp.d[ oid ];
					for( fld in cached._d ) {
					    //add new getters/setters
					    cached['get_'+fld] = (function(fl) { return function() { return this.get(fl) } } )(fld);
					}
				    }
				}
			    }
		            if( typeof params.passhandler === 'function' ) {
				if( typeof resp.r === 'object' ) {
				    params.passhandler( root._create_obj( ret.r, this._app_id ) );
				} else if( typeof resp.r === 'undefined' ) {
				    params.passhandler();
				} else {
				    params.passhandler( resp.r.substring( 1 ) );
				}
		            }
			} else if( typeof params.failhandler === 'function' ) {
		            params.failhandler(resp.err);
			} //error case. no handler defined
                    } else {
			console.log( "Success reported but no response data received" );
                    }
		} catch(err) {
		    root._error(err);
		}
	    } )
	} ).submit();
    }, //upload_message

    _cache_size:function() { //used for unit tests
        var i = 0;
        for( v in this.objs ) {
            ++i;
        }
        return i;
    },

    // TODO : use prototype for the _create_obj
    _create_obj:function(data,app_id) { //creates the javascript proxy object for the perl object.
	var root = this;
	if( data.id != null && typeof data.id !== 'undefined' && root._is_in_cache( data.id ) ) {
	    return root.objs[ data.id + '' ];
	}
	var retty = (function(x,ai) {
	    var o = {
		_app_id:ai,
                _dirty:false,
		_d:{},
		id:x.id+'',
		class:x.c,
                _staged:{},
		length:function() {
		    var cnt = 0;
		    for( key in this._d ) {
			++cnt;
		    }
		    return cnt;
		},
		equals:function(oth) {
		    return typeof oth === 'object' && oth.id && oth.id == this.id;
		},
		keys:function() {
		    return Object.keys( this._d );
		},
		values:function() {
		    var thing = this;
		    return this.keys().map(function(a) { return thing.get(a); } );
		},
		sort:function(sortfun) {
		    var res = this.values().sort( sortfun );
		    return res;
		},
		wrap_list:function( args ) {
		    return this.wrap( args, false ); 
		},
		wrap_hash:function( args ) {
		    return this.wrap( args, true );
		},
		wrap:function( args, is_hash ) {
		    var host_obj = this;
		    var fld = args[ 'collection_name' ]
		    var ol = host_obj.count( fld );

		    // see if the whole list can be obtained at once
		    var page_out_list = fld.charAt( 0 ) == '_'  || ol > (args[ 'threshhold' ] || 200);

		    if( ! page_out_list ) {
			var collection_obj = host_obj.get( fld );
		    }
		    return {
			page_out_list      : page_out_list,
			collection_obj     : collection_obj,
			id                 : host_obj.id,
			host_obj           : host_obj,
			field              : fld,
			start              : args[ 'start' ] || 0,
			page_out_list      : page_out_list,
			page_size     : args[ 'size' ],
			search_values : args[ 'search_value'  ] || undefined,
			search_fields : args[ 'search_field'  ] || undefined,
			sort_fields   : args[ 'sort_fields'   ] || undefined,
			hash_search_value : args[ 'hash_search_value' ] || undefined,
			sort_reverse  : args[ 'sort_reverse'  ] || false,
			is_hash       : is_hash,
			full_size : function() {
			    var me = this;
			    if( me.page_out_list ) {
				return me.host_obj.count( me.field );
			    }
			    if( me.is_hash ) {
 				 return Object.size( me.collection_obj._d );
			    }
			    return me.collection_obj.length();
			},
			to_list : function() {
			    var me = this;
			    if( me.page_out_list ) {
				me.length = me.host_obj.count( {
				    name  : me.field, 
				    search_fields : me.search_fields,
				    search_terms  : me.search_values,
				} );
				var res = me.host_obj.paginate( { 
				    name  : me.field, 
				    limit : me.page_size,
				    skip  : me.start,
				    search_fields : me.search_fields,
				    search_terms  : me.search_values,
				    reverse : me.sort_reverse,
				    sort_fields : me.sort_fields
				} );
				return res.to_list();
			    }
			    else {
				var ret = [];
				if( ! me.collection_obj ) return ret;
				var olist = me.collection_obj.to_list();

				if( this.sort_fields ) {
				    olist = olist.sort( function( a, b ) { 
					for( var i=0; i<me.sort_fields.length; i++ ) {
					    if( typeof a === 'object' && typeof b === 'object' ) 
						return a.get( me.sort_fields[i] ).toLowerCase().localeCompare( b.get( me.sort_fields[i] ).toLowerCase() );
					    return 0;
					}
				    } );
				    if( this.sort_reverse ) olist.reverse();
				}

				this.length = 0;
				for( var i=0; i < olist.length; i++ ) {
				    if( this.search_values && this.search_fields && this.search_values.length > 0 && this.search_fields.length > 0 ) {
					if( this.search_fields && this.search_fields.length > 0 ) {
					    var match = false;
					    for( var j=0; j<this.search_values.length; j++ ) {
						for( var k=0; k<this.search_fields.length; k++ ) {
						    match = match || typeof olist[ i ] === 'object' && olist[ i ].get( this.search_fields[k] ).toLowerCase().indexOf( this.search_values[ j ].toLowerCase() ) != -1;
						}
					    }
					    if( match ) {
						this.length++;
						if( i >= this.start && ret.length < this.page_size ) 
						    ret.push( olist[i] );
					    }
					}
				    }
				    else {
					this.length++;
					if( i >= this.start && ret.length < this.page_size ) 
					    ret.push( olist[i] );
				    }
				}
				return ret;
			    }
			},
			to_hash : function() {
			    var me = this;
			    if( me.page_out_list ) {
				me.length = me.host_obj.count( {
				    name  : me.field, 
				    search_fields : me.search_fields,
				    search_terms  : me.search_values,
				} );

				var res = me.host_obj.paginate( { 
				    name  : me.field, 
				    limit : me.page_size,
				    skip  : me.start,
				    search_fields : me.search_fields,
				    search_terms  : me.search_values,
				    reverse : me.sort_reverse,
				    sort_fields : me.sort_fields,
				    return_hash : true,
				} );
				return res.to_hash();
			    }
			    else {
				var ret = {};
				if( ! me.collection_obj ) return ret;
				var ohash  = me.collection_obj.to_hash();
				var hkeys = me.collection_obj.keys();
				
				hkeys.sort();
				if( me.sort_reverse ) hkeys.reverse();

				me.length = 0;
				for( var i=0; i < hkeys.length && me.length < me.page_size; i++ ) {
				    if( me.search_values && me.search_fields && me.search_values.length > 0 && me.search_fields.length > 0 ) {
					if( me.search_fields && me.search_fields.length > 0 ) {
					    var match = false;
					    for( var j=0; j<me.search_values.length; j++ ) {
						for( var k=0; k<me.search_fields.length; k++ ) {
						    match = match || typeof ohash[ hkeys[ i ] ] === 'object' && ohash[ hkeys[ i ] ].get( me.search_fields[k] ).toLowerCase().indexOf( me.search_values[ j ].toLowerCase() ) != -1;
						}
					    }
					    if( match ) {
						me.length++;
						if( i >= me.start && me.length < me.page_size ) {
						    ret[ hkeys[ i ] ] = ohash[ hkeys[ i ] ];
						}
					    }
					}
				    }
				    else {
					if( i >= me.start && me.length < me.page_size ) {
					    var k = hkeys[ i ];
					    if( ! me.hash_search_value || key.toLowerCase().indexOf( this.hash_search_value ) != -1 ) {
						ret[ k ] = ohash[ k ];
						me.length++;
					    }
					}
				    }
				}
				return ret;
			    }
			},
			set_hash_search_criteria:function( hash_search ) {
			    this.hash_search_value = hash_search;
			},
			set_search_criteria:function( fields, values ) {
			    if( ! values ) {
				this.search_fields = undefined;
				return;
			    }
			    var has_val = false;
			    for( var i=0; i<values.length; i++ ) {
				has_val = has_val || (values[ i ] && values[ i ] != '' );
			    }
			    if( has_val ) {
				this.search_fields = fields;
				this.search_values = values;
			    }
			    else {
				this.search_fields = undefined;
			    }
			}, //set_search_criteria
			get : function( idx ) {
			    if( this.page_out_lists ) {
				if( this.is_hash )
				    return this.host_obj.hash_fetch( { name : this.field, index : idx + this.start } );
				return this.host_obj.list_fetch( { name : this.field, index : idx + this.start } );
			    }
			    if( this.is_hash ) {
				return this.collection_obj.get( idx );
			    }
			    return this.collection_obj.get( this.start + idx );
			},
			add_to : function( data ) {
			    return this.collection_obj.add_to( data );
			},
			remove_from : function( data ) {
			    return this.collection_obj.remove_from( data );
			},
			seek:function(topos) {
			    this.start = topos;
			},
			forwards:function(){
			    var towards = this.start + this.page_size;
			    this.start = towards > this.length ? (this.length-1) : towards;
			},
			can_rewind : function() {
			    return this.start > 0;
			},
			can_fast_forward : function() {
			    return this.start + this.page_size < this.length;
			},
			back:function(){
			    var towards = this.start - (this.page_size);
 			    this.start = towards < 0 ? 0 : towards;
			},
			first:function(){         
			    this.start = 0;
			},
			last:function(){
			    this.start = this.full_size() - this.page_size;
			}
		    };
		}, //wrap

		paginator:function( fieldname, is_hash, size, start ) {
		    var obj = this;
		    var st = start || 0;
		    var pag = {
			field      : fieldname,
			full_size  : 1 * obj.count( fieldname ),
			page_size  : size,
			start      : st,
			contents   : [],
			is_hash    : is_hash,
			get : function( idx ) {
			    return this.contents[ idx ];
			},
			page_count : function() {
			    if( this.is_hash ) {
				return Object.size( this.contents );
			    } else {
				return this.contents.length;
			    }
			},
			seek : function( idx ) {			    
			    if( this.is_hash ) {
				this.contents = obj.paginate( { name : this.field, limit : this.page_size, skip : idx, return_hash : true } ).to_hash();
			    }
			    else {
				var res = obj.paginate( { name : this.field, limit : this.page_size, skip : idx } );
				this.contents = [];
				for( var i=0; i < res.length(); i++ ) {
				    this.contents.push( res.get( i ) );
				}			
			    }
			    this.start = idx;
			},
			can_rewind : function() {
			    return this.start > 0;
			},
			rewind : function() {
			    if( this.start > 0 ) {
				var to = this.start - this.page_size;
				if( to < 0 ) { to = 0 };
				this.seek( to );
			    }
			},
			can_fast_forward : function() {
			    return this.start + this.page_size < this.full_size;
			},
			fast_forward : function() {
			    var to = this.start + this.page_size;
			    if( to < this.full_size ) {
				this.seek( to );
			    }
			},
			end: function() {
			    this.seek( this.full_size - this.page_size );
			},
			to_beginning : function() { 
			    this.seek( 0 );
			}
		    };
		    pag.seek( st );
		    return pag;
		}, // paginator
		list_paginator:function( listname, size, start ) {
		    return this.paginator( listname, false, size, start );
		},
		hash_paginator:function( hashname, size, start ) {
		    return this.paginator( hashname, true, size, start );
		}

	    };
	    if( o.class == 'HASH' ) {
		o.to_hash = function() {
		    var hash = {};
		    for( var key in this._d ) {
			hash[ key ] = this.get( key );
		    }
		    return hash;
		};
	    }
	    else if( o.class == 'ARRAY' ) {
		o.to_list = function() {
		    var list = [];
		    for( var i=0; i < this.length(); i++ ) {
			list[i] = this.get(i);
		    }
		    return list;
		};
	    }
	    else {
		if( typeof x.m === 'object' && x.m !== null ) { // set methods
		    for( m in x.m ) {
			o[x.m[m]] = (function(key,thobj) {
			    return function( params, passhandler, failhandler, use_async ) {
				return root.message( {
				    async: use_async ? true : false,
				    app_id:this._app_id,
				    cmd:key,
				    data:params,
				    failhandler:failhandler,
                                    obj_id:this.id,
				    passhandler:passhandler,
				    wait:true
				} ); //sending message
			    } } )(x.m[m],x);
		    } //each method
		} // if methods were included in the return value of the call
	    } // if object

	    o.get = function( key ) {
		var val = this._staged[key] || this._d[key];
		if( typeof val === 'undefined' ) return false;
		if( typeof val === 'object' ) return val;
		if( typeof val === 'function' ) return val;

		if( val.substring(0,1) != 'v' ) {
		    var obj = root.objs[val+''] || $.yote.fetch_root().fetch(val).get(0);
		    obj._app_id = this._app_id;
                    return obj;
		}
		return val.substring(1);
	    };

	    o.get_list_handle = function( key ) {
		// this returns an object that is a handle to a container. It does not load the
		// container contents at once, but provides get and set that contact the server to load
		// or set things

		var ret = {
		    item          : this,
		    container_key : key,
		    get           : function( idx ) {
			return this.item.list_fetch( { name : this.container_key, index : idx } );
		    },
		    push          : function( key, val ) {
			return this.item.insert_at( { name : this.container_key, item : val } );			
		    }
		};
		return ret;
	    }; //get_list_handle

	    o.get_hash_handle = function( key ) {
		// this returns an object that is a handle to a container. It does not load the
		// container contents at once, but provides get and set that contact the server to load
		// or set things
		var ret = {
		    item          : this,
		    container_key : key,
		    get           : function( hkey ) {
			return this.item.hash_fetch( { name : this.container_key, key : hkey } );
		    },
		    set           : function( hkey, val ) {
			return this.item.hash( { name : this.container_key, key : hkey, value : val } );			
		    }
		};
		return ret;
	    }; //get_hash_handle


	    o.set = function( key, val, failh, passh ) {
		this._stage( key, val );
		this._send_update( undefined, failh, passh );
		delete this._staged[ key ];
		return val;
	    };

	    // get fields
	    if( typeof x.d === 'object' && x.d !== null ) {
		for( fld in x.d ) {
		    var val = x.d[fld];
		    if( typeof val === 'object' && val != null ) {
			o._d[fld] = (function(xx) { return root._create_obj( xx, app_id ); })(val);
		    }
		    else {
			o._d[fld] = (function(xx) { return xx; })(val);
		    }
		    o['get_'+fld] = (function(fl) { return function() { return this.get(fl) } } )(fld);
		    o['set_'+fld] = (function(fl) { return function(val,fh,ph) { return this.set(fl,val,fh,ph) } } )(fld);
		}
	    }

            // stages functions for updates
            o._stage = function( key, val ) {
                if( this._staged[key] !== root._translate_data( val ) ) {
                    this._staged[key] = root._translate_data( val );
                    this._dirty = true;
                }
            }

            // resets staged info
            o._reset = function( field ) {
		if( field ) {
		    delete this._staged[ field ];
		} else {
                    this._staged = {};
		}
            }

            o._is_dirty = function(field) {
                return typeof field === 'undefined' ? this._dirty : this._staged[field] !== this._d[field] ;
            }

            // sends data structure as an update, or uses staged values if no data
            o._send_update = function(data,failhandler,passhandler) {
                var to_send = {};
                if( this.c === 'Array' ) {
                    to_send = Array();
                }
                if( typeof data === 'undefined' ) { //sending from staged
                    for( var key in this._staged ) {
                        if( this.c === 'Array' ) {
                            to_send.push( root._untranslate_data(this._staged[key]) );
                        } else {
                            to_send[key] = root._untranslate_data(this._staged[key]);
                        }
                    }
                } else {
                    for( var key in data ) {
                        if( this.c === 'Array' ) {
                            to_send.push( data[key] );
                        } else {
                            to_send[key] = data[key];
                        }
                    }
                }
                var needs = 0;
                for( var key in to_send ) {
                    needs = 1;
                }
                if( needs == 0 ) { return; }

                root.message( { //for send update
                    app_id:this._app_id,
                    async:false,
                    data:to_send,
                    cmd:'update',
                    failhandler:function() {
                        if( typeof failhandler === 'function' ) {
                            failhandler();
                        }
                    },
                    obj_id:this.id,
                    passhandler:(function(td) {
                        return function() {
                            o._staged = {};
                            if( typeof passhandler === 'function' ) {
                                passhandler();
                            }
                        }
                    } )(to_send),
                    wait:true
                } );
            }; //_send_update

	    if( o.id && o.id.substring(0,1) != 'v' ) {
		root.objs[o.id+''] = o;
	    }
	    return o;
        } )(data,app_id);
	return retty;
    }, //_create_obj

    _disable:function() {
	if( $( 'body' ).css("cursor") !== "wait" ) {
            this.enabled = $(':enabled');
	    $.each( this.enabled, function(idx,val) { val.disabled = true; } );
            $("body").css("cursor", "wait");
	}
    }, //_disable

    _dump_cache:function() {
        this.objs = {};
	this.apps = {};
    },

    // generic server type error
    _error:function(msg) {
        console.log( "a server side error has occurred" );
        console.log( msg );
    },

    _functions_in:function( thing ) {
	var to_ret, res;
	if( typeof thing === 'function' ) return [thing];
	if( typeof thing === 'object' || typeof thing === 'array' ) {
	    to_ret = [];
	    for( x in thing ) {
		res = this._functions_in( thing[ x ] );
		for( y in res ) {
		    to_ret.push( res[ y ] );
		}
	    }
	    return to_ret;
	}
	return [];
    }, //_functions_in

    _is_in_cache:function(id) {
        return typeof this.objs[id+''] === 'object' && this.objs[id+''] != null;
    },

    _reenable:function() {
        $.each( this.enabled, function(idx,val) { val.disabled = false } );
        $("body").css("cursor", "auto");
    }, //_reenable

    _translate_data:function(data,run_functions) {
        if( typeof data === 'undefined' || data == null ) {
            return undefined;
        }
        if( typeof data === 'object' ) {
            if( data.id  && typeof data._d !== 'undefined' && data.id.substring(0,1) != 'v' ) {
                return data.id;
            }
            // this case is for paramers being sent thru message
            // that will not get ids.
            var ret;
	    if (data instanceof Array) {
		ret = [];
	    } else {
		ret = Object();
	    }
            for( var key in data ) {
                ret[key] = this._translate_data( data[key], run_functions );
            }
            return ret;
        }
	if( typeof data === 'function' ) {
	    if( run_functions )
		return data();
	    return data;
	}
        return 'v' + data;
    }, //_translate_data

    _untranslate_data:function(data) {
	if( typeof data === 'function' ) {
	    return data;
	}
        if( data.substring(0,1) == 'v' ) {
            return data.substring(1);
        }
        if( this._is_in_cache(data) ) {
            return this.objs[data+''];
        }
        console.log( "Don't know how to translate " + data);
    }, //_untranslate_data

    upload_count: 0,
    iframe_count: 0

}; //$.yote
