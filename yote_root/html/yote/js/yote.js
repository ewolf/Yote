/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Version 0.099
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

Object.size = function(obj) {
    var size = 0, key;
    for (key in obj) {
        if (obj.hasOwnProperty(key)) size++;
    }
    return size;
};


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
    debug:true,

    init:function() {
        var t = $.cookie('yoken');
	$.yote.token = t || 0;

	var root = this.fetch_root();
        if( typeof t === 'string' ) {
            var ret = root.token_login( $.yote.token );
	    if( typeof ret === 'object' ) {
		$.yote.token     = t;
		this.login_obj = ret;
	    }
        }

	$.yote.guest_token = root.guest_token();

	return ret;
    }, //init

    create_login:function( handle, password, email, passhandler, failhandler ) {
	var root = this.fetch_root();
	if( typeof root === 'object' ) {
	    root.create_login( { h:handle, p:password, e:email },
			       function(res) {
				   $.yote.token = res.get( 't' ) || 0;
				   $.yote.login_obj = res.get( 'l' );
				   $.cookie( 'yoken', $.yote.token );
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
    }, //create_login


    fetch_account:function() {
	return this.fetch_root().account();
    },

    fetch_app:function(appname,passhandler,failhandler) {
	var root = this.fetch_root();
	if( typeof root === 'object' ) {
	    var ret = root.fetch_app_by_class( appname );
	    ret._app_id = ret.id;
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
	}
	return r;
    }, //fetch_root


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
			    $.cookie( 'yoken', $.yote.token );
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
	$.yote.token = 0;
	$.cookie( 'yoken', '' );
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
        var get_data = $.yote.token + "/" + $.yote.guest_token + "/" + wait + "/" + $.base64.encode( JSON.stringify( { d : data } ) );
	var resp;

        if( $.yote.debug == true ) {
	    console.log("\noutgoing " + url + '-------------------------' );
	    console.log( data );
//	    console.log( JSON.stringify( {d:data} ) );
	}

	$.ajax( {
	    async:async,
	    cache: false,
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
				var cached = root.objs[ oid ];
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
	    type:'GET',
	    url:url + '/' + get_data
	} );
        if( ! async ) {
            root._reenable();
            return resp;
        }
    }, //message

    remove_login:function( handle, password, email, passhandler, failhandler ) {
	var root = this.fetch_root();
	if( typeof root === 'object' ) {
	    root.remove_login( { h:handle, p:password, e:email },
			       function(res) {
				   $.yote.token = 0;
				   $.yote.login_obj = undefined;
				   passhandler(res);
			       },
			       failhandler );
	} else if( typeof failhanlder === 'function' ) {
	    failhandler('lost connection to yote server');
	} else {
	    _error('lost connection to yote server');
	}
    }, //remove_login

    /* the upload function takes a selector returns a function that sets the name of the selector to a particular value,
       which corresponds to the parameter name in the inputs.
       For example some_yote_obj->do_something( { a : 'a data', file_up = upload( '#myfileuploader' ) } )
    */
    upload:function( selector_id ) {
	var uctxt = 'u' + this.upload_count++;
	$( selector_id ).attr( 'name', uctxt );
	return (function(uct, sel_id) {
	    return function( return_selector_id ) { //if given no arguments, just returns the name given to the file input contro
		if( return_selector_id ) return sel_id;
		return uctxt;
	    };
	} )( uctxt, selector_id );
    }, //upload

    /*
      This is called automatically by message if there is an upload involved. It is not meant to be invoked directly.
     */
    upload_message:function( params, uploads ) {
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
                    if( typeof resp !== 'undefined' ) {
			if( typeof resp.err === 'undefined' ) {
			    //dirty objects that may need a refresh
			    if( typeof resp.d === 'object' ) {
				for( var oid in resp.d ) {
				    if( root._is_in_cache( oid ) ) {
					var cached = root.objs[ oid ];
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

    _cache_size:function() {
        var i = 0;
        for( v in this.objs ) {
            ++i;
        }
        return i;
    },

    _create_obj:function(data,app_id) {
	var root = this;
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
		    var k = []
		    for( key in this._d ) {
			k.push( key );
		    }
		    return k;
		},
		values:function() {
		    var thing = this;
		    return this.keys().map(function(a) { return thing.get(a); } );
		},
		sort:function(sortfun) {
		    var res = this.values().sort( sortfun );
		    return res;
		},
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
				this.contents = obj.paginate_hash( [ this.field, this.page_size, idx ] ).to_hash();
			    } else {
				var res = obj.paginate( [ this.field, this.page_size, idx ] );
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
			to_end: function() {
			    this.seek( this.full_size - this.page_size );
			},
			to_beginning : function() { 
			    this.seek( 0 );
			}
		    };
		    pag.seek( st );
		    return pag;
		},
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
		if( (0+val) > 0 || val.substring(0,1) != 'v' ) {
		    var obj = root.objs[val] || $.yote.fetch_root().fetch(val).get(0);
		    obj._app_id = this._app_id;
                    return obj;
		}
		return val.substring(1);
	    };

	    o.set = function( key, val, failh, passh ) {
		this._stage( key, val );
		this._send_update( undefined, failh, passh );
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
		    o['set_'+fld] = (function(fl,fh,ph) { return function(val) { return this.set(fl,val,fh,ph) } } )(fld);
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
                if( typeof data === 'undefined' ) {
                    for( var key in this._staged ) {
                        if( key.match(/^[A-Z]/) ) {
                            if( this.c === 'Array' ) {
                                to_send.push( root._untranslate_data(this._staged[key]) );
                            } else {
                                to_send[key] = root._untranslate_data(this._staged[key]);
                            }
                        }
                    }
                } else {
                    for( var key in data ) {
                        if( key.match(/^[A-Z]/) ) {
                            if( this.c === 'Array' ) {
                                to_send.push( data[key] );
                            } else {
                                to_send[key] = data[key];
                            }
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
                            for( var key in td ) {
                                o._d[key] = root._translate_data(td[key]);
                            }
                            o._staged = {};
                            if( typeof passhandler === 'function' ) {
                                passhandler();
                            }
                        }
                    } )(to_send),
                    wait:true
                } );
            };

	    if( o.id && o.id.substring(0,1) != 'v' ) {
		root.objs[o.id] = o;
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
        return typeof this.objs[id] === 'object' && this.objs[id] != null;
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
        if( data.substring(0,1) == 'v' ) {
            return data.substring(1);
        }
        if( this._is_in_cache(data) ) {
            return this.objs[data];
        }
        console.log( "Don't know how to translate " + data);
    }, //_untranslate_data

    upload_count: 0,
    iframe_count: 0

}; //$.yote
