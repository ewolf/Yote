/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Here are the following public yote calls :
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

$.yote = {
    token:null,
    err:null,
    objs:{},
    debug:true,

    init:function() {
        var t = $.cookie('yoken');
	$.yote.token = t;

	var root = this.fetch_root();
        if( typeof t === 'string' ) {
            var ret = root.token_login( $.yote.token );
	    if( typeof ret === 'object' ) {
		$.yote.token     = t;
		this.login_obj = ret;
	    }
        }
    }, //init

    fetch_root:function() {
	return this.objs[1] || this._create_obj( this.message( {
            async:false,
            cmd:'fetch_root',
	    wait:true
	} ).r, 1 );
	
    }, //fetch_root

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

    fetch_account:function() {
	return this.fetch_root().account();
    },

    load_direct_descendents:function( app, obj ) {
	var desc = app.multi_fetch( obj );
	for( var i=0; i<desc.length(); i++ ) {
	    desc.get(i);
	}
    }, //load_direct_descendents

    create_login:function( handle, password, email, passhandler, failhandler ) {
	var root = this.fetch_root();
	if( typeof root === 'object' ) {
	    root.create_login( { h:handle, p:password, e:email }, 
			       function(res) {
				   $.yote.token = res.r.d.t.substring(1);
				   $.yote.login_obj = $.yote._create_obj(res.r.d.l);
				   $.cookie( 'yoken', $.yote.token );
				   passhandler(res);
			       },
			       failhandler );
	    return $.yote.login_obj;
	} else if( typeof failhanlder === 'function' ) {
	    failhandler('lost connection to yote server');
	} else {
	    _error('lost connection to yote server');
	}
    }, //create_login

    login:function( handle, password, passhandler, failhandler ) {
	var root = this.fetch_root();
	if( typeof root === 'object' ) {
	    root.login( { h:handle, p:password }, 
			function(res) {
			    $.yote.token = res.r.d.t.substring(1);
			    $.yote.login_obj = $.yote._create_obj(res.r.d.l);
			    $.cookie( 'yoken', $.yote.token );
			    passhandler(res);
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
	$.yote.login_obj = undefined;
	$.yote.token = undefined;
	$.cookie( 'yoken', '' );
    }, //logout

    remove_login:function( handle, password, email, passhandler, failhandler ) {
	var root = this.fetch_root();
	if( typeof root === 'object' ) {
	    root.remove_login( { h:handle, p:password, e:email }, 
			       function(res) {
				   $.yote.token = undefined;
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

    get_login:function() {
	return this.login_obj;
    }, //get_login

    is_logged_in:function() {
	return typeof this.login_obj === 'object';
    }, //is_logged_in

    _dump_cache:function() {
        this.objs = {};
    },

    _is_in_cache:function(id) {
        return typeof this.objs[id] === 'object' && this.objs[id] != null;
    },

    _cache_size:function() {
        var i = 0;
        for( v in this.objs ) {
            ++i;
        }
        return i;
    },

    _create_obj:function(data,app_id) {
	var root = this;
	return (function(x,ai) {
	    var o = {
		_app_id:ai,
                _dirty:false,
		_d:{},
		id:x.id,
		class:x.c,
                _stage:{},
		length:function() {
		    var cnt = 0;
		    for( key in this._d ) {
			++cnt;
		    }
		    return cnt;
		},
		keys:function() {
		    var k = []
		    for( key in this._d ) {
			k.push( key );
		    }
		    return k;
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
	    if( o.class == 'ARRAY' ) {
		o.to_list = function() {
		    var list = [];
		    for( var i=0; i < this.length(); i++ ) {
			list[i] = this.get(i);
		    }
		    return list;
		};
	    }
	    /*
	      assign methods
	    */
	    if( typeof x.m === 'object' ) {
		for( m in x.m ) {
		    o[x.m[m]] = (function(key) {
			return function( params, passhandler, failhandler ) {
			    var ret = root.message( {
				async:false,
				app_id:this._app_id,
				cmd:key,
				data:params,
				failhandler:failhandler,
                                obj_id:this.id,
				passhandler:passhandler,
				wait:true,
				t:$.yote.token
			    } ); //sending message
			    

			    //dirty objects that may need a refresh
			    if( typeof ret.d === 'object' ) {
				for( var oid in ret.d ) {
				    if( root._is_in_cache( oid ) ) {
					var cached = root.objs[ oid ];
					for( fld in cached._d ) {
					    //take off old getters/setters
					    delete cached['get_'+fld];
					}
					cached._d = ret.d[ oid ];
					for( fld in cached._d ) {
					    //add new getters/setters
					    cached['get_'+fld] = (function(fl) { return function() { return this.get(fl) } } )(fld);
					}
				    }
				}
			    }
			    if( typeof ret.r === 'object' ) {
				return root._create_obj( ret.r, this._app_id );
			    } else {
                                if( typeof ret.r === 'undefined' ) {
				    if( typeof failhandler === 'function' ) {
                                        failhandler('no return value');
				    }
				    return undefined;
                                }
				return ret.r.substring(1);
			    }
			} } )(x.m[m]);
		} //each method
	    } //methods

	    o.get = function( key ) {
		var val = this._stage[key] || this._d[key];
		if( typeof val === 'undefined' ) return false;
		if( typeof val === 'object' ) return val;
		if( (0+val) > 0 ) {
		    var obj = root.objs[val] || $.yote.fetch_root().fetch(val).get(0);
                    if( this._stage[key] == val ) {
                        this._stage[key] = obj;
                    } else {
                        this._d[key] = obj;
                    }
                    return obj;
		}
		return val.substring(1);
	    };

	    // get fields
	    if( typeof x.d === 'object' ) {
		for( fld in x.d ) {
		    var val = x.d[fld];
		    if( typeof val === 'object' ) {
			o._d[fld] = (function(xx) { return root._create_obj( xx, o._app_id ); })(val);
			
		    } else {
			o._d[fld] = (function(xx) { return xx; })(val);
		    }
		    o['get_'+fld] = (function(fl) { return function() { return this.get(fl) } } )(fld);
		}
	    }

            // stages functions for updates
            o.stage = function( key, val ) {
                if( this._stage[key] !== root._translate_data( val ) ) {
                    this._stage[key] = root._translate_data( val );
                    this._dirty = true;
                }
            }

            // resets staged info
            o.reset = function( field ) {
		if( field ) {
		    delete this._stage[ field ];
		} else {
                    this._stage = {};
		}
            }

            o.is_dirty = function(field) {
                return typeof field === 'undefined' ? this._dirty : this._stage[field] !== this._d[field] ;
            }

            // sends data structure as an update, or uses staged values if no data
            o.send_update = function(data,failhandler,passhandler) {
                var to_send = {};
                if( this.c === 'Array' ) {                        
                    to_send = Array();
                }
                if( typeof data === 'undefined' ) {
                    for( var key in this._stage ) {
                        if( key.match(/^[A-Z]/) ) {
                            if( this.c === 'Array' ) {
                                to_send.push( root._untranslate_data(this._stage[key]) );
                            } else {
                                to_send[key] = root._untranslate_data(this._stage[key]);
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
                
                root.message( {
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
                            o._stage = {};
                            if( typeof passhandler === 'function' ) {
                                passhandler();
                            }
                        }
                    } )(to_send),
                    wait:true 
                } );
            };

	    if( (0 + x.id ) > 0 ) {
		root.objs[x.id] = o;
	    }
	    return o;
        } )(data,app_id);
    }, //_create_obj

    // generic server type error
    _error:function(msg) {
        console.log( "a server side error has occurred" );
        console.log( msg );
    },
    
    _translate_data:function(data,run_functions) {
        if( typeof data === 'undefined' || data == null ) {
            return undefined;
        }
        if( typeof data === 'object' ) {
            if( data.id + 0 > 0 && typeof data._d !== 'undefined' ) {
                return data.id;
            }
            // this case is for paramers being sent thru message
            // that will not get ids.
            var ret = Object();
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

    _disable:function() {
        this.enabled = $(':enabled');
	$.each( this.enabled, function(idx,val) { val.disabled = true; } );
        $("body").css("cursor", "wait");
    }, //_disable
    
    _reenable:function() {
        $.each( this.enabled, function(idx,val) { val.disabled = false } );
        $("body").css("cursor", "auto");
    }, //_reenable

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
    
    upload_count: 0,
    iframe_count: 0,

    /* the upload function takes a selector returns a function that sets the name of the selector to a particular value,
       which corresponds to the parameter name in the inputs.
       For example some_yote_obj->do_somehingt( { a : 'a data', file_up = upload( '#myfileuploader' ) } )
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

    /* general functions */
    message:function( params ) {
        var root   = this;
        var data   = root._translate_data( params.data || {} );
        var async  = params.async == true ? 1 : 0;
	var wait   = params.wait  == true ? 1 : 0;
        var url    = params.url;
        var app_id = params.app_id;
        var cmd    = params.cmd;
        var obj_id = params.obj_id; //id to act on
        if( async == 0 ) {
            root._disable();
        }
	root.upload_count = 0;

        app_id = app_id || '';
        obj_id = obj_id || '';
        var url = '/_/' + app_id + '/' + obj_id + '/' + cmd;

	var uploads = root._functions_in( data );
	if( uploads.length > 0 ) {
	    return root.upload_message( params, uploads );
	}

        var put_data = {
            d:$.base64.encode(JSON.stringify( {d:data} ) ),
            t:$.yote.token,
            w:wait
        };
	var resp;

        if( $.yote.debug == true ) {
	    console.log('outgoing ' + url );  
	    console.log( data );
	    console.log( JSON.stringify( {d:data} ) );
	    console.log( put_data ); 
	}

	$.ajax( {
	    async:async,
	    cache: false,
	    data:put_data,
	    dataFilter:function(a,b) {
		if( $.yote.debug == true ) {
		    console.log('incoming '); console.log( a );
		}
		return a; 
	    },
	    error:function(a,b,c) { root._error(a); },
	    success:function( data ) {
                if( typeof data !== 'undefined' ) {
		    resp = data; //for returning synchronous
		    if( typeof data.err === 'undefined' ) {
		        if( typeof params.passhandler === 'function' ) {
			    params.passhandler(data);
		        }
		    } else if( typeof params.failhandler === 'function' ) {
		        params.failhandler(data.err);
                    } //error case. no handler defined 
                } else {
                    console.log( "Success reported but no response data received" );
                }
	    },
	    type:'POST',
	    url:url
	} );
        if( async == 0 ) {
            root._reenable();
            return resp;
        }
    }, //message
    
    upload_message:function( params, uploads ) {
        var root   = this;
        var data   = root._translate_data( params.data || {}, true );
        var async  = params.async == true ? 1 : 0;
	var wait   = params.wait  == true ? 1 : 0;
        var url    = params.url;
        var app_id = params.app_id;
        var cmd    = params.cmd;
        var obj_id = params.obj_id; //id to act on
        if( async == 0 ) {
            root._disable();
        }

        app_id = app_id || '';
        obj_id = obj_id || '';
        var url = location.protocol+'//'+location.hostname+(location.port ? ':'+location.port: '') + 
	    '/_u/' + app_id + '/' + obj_id + '/' + cmd;

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
	$( '#' + form_id ).append( '<input type=hidden name=w value="' + wait + '">');
    
	for( var i=0; i<cb_list.length; i++ ) {
	    cb_list[ i ].removeAttr('checked');
	    cb_list[ i ].attr('checked', true);
	}
    
	var resp;
	var xx = form_sel.submit(function() {
	    iframe.load(function() {		
		var contents = $(this).contents().get(0).body.innerHTML;
		$( '#' + iframe_name ).remove();
		try {
		    resp = JSON.parse( contents );
		    
                    if( typeof resp !== 'undefined' ) {
			if( typeof resp.err === 'undefined' ) {
		            if( typeof params.passhandler === 'function' ) {
				params.passhandler(data);
		            }
			} else if( typeof params.failhandler === 'function' ) {
		            params.failhandler(data.err);
			} //error case. no handler defined 
                    } else {
			console.log( "Success reported but no response data received" );
                    }
		} catch(err) {
		    root._error(err); 
		}
	    } )
	} ).submit();
    } //upload_message
    
}; //$.yote


1