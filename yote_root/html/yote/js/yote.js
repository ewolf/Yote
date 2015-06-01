/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Version 0.203
 */

/*
  Upon script load, see if a port was explicity given in the script
  tag calling this file. If there is a port specified, use that
  location as an absolute location when making the yote ajax calls.
  If the normal port is used, that means the script is called from the
  same place as the page and relative urls can be used for the ajax calls.
*/
var scripts = document.getElementsByTagName('script');
var index = scripts.length - 1;
var myScriptUrl = scripts[index].src;
var ma = myScriptUrl.match( /^((https?:\/\/)?[^\/]+(:(\d+))?)\// );
var yote_src_url = ma && ma.length > 1 ? ma[ 1 ] : '';

$.yote = {
    url:yote_src_url,
    has_updated :false,
    guest_token:0,
    token:0,
    port:null,
    err:null,
    objs:{},
    apps:{},
    debug:false,
    app:null,
    root:null,
    need_reinit:false,

    _ids:0,
    _next_id:function() {
        return '__yidx_'+this._ids++;
    }, //_next_id
    _pag_list_cache : {},
    _pag_hash_cache : {},


    init:function( appname, token ) {
        token = token ? token : $.cookie('yoken');
	    $.yote.token = token || 0;
        var ret;
	    this.message( {
	        async:false,
	        cmd:'fetch_initial',
	        data:{ t:token,a:appname },
	        passhandler:function( initial_data ) {
		        if( typeof initial_data === 'object' && initial_data.get(  'root' ) && initial_data.get(  'app' ) ) {
		            var yote_root = initial_data.get(  'root' );
                    yote_root._app_id = yote_root.id;
		            $.yote.yote_root = yote_root;
		            $.yote.objs[ yote_root.id ] = yote_root;

		            var app = initial_data.get( 'app' ) || yote_root;
		            app._app_id = app.id;
		            $.yote._app_id = app.id;
		            $.yote.default_app = app;
		            $.yote.default_appname = appname;
		            $.yote.objs[ app.id ] = app;

		            $.yote.login_obj   = initial_data.get(  'login' );
		            $.yote.acct_obj    = initial_data.get(  'account' );
                    $.yote.acct_obj._app_id = app.id;

		            $.yote.guest_token = initial_data.get(  'guest_token' );

		            ret = app;
		        }
		        else {
		            console.log( "ERROR in init for app '" + appname + "' Load did not work" );
		        }
	        },
	        failhandler:function( err ) {
		        console.log( "ERROR in init for app '" + appname + "' : " + err );
	        }
	    } );
        return ret;
    }, //init

    reinit:function( token ) {
	    if( ! this.default_app || this.need_reinit ) {
	        this.init( this.default_appname, token );
	        this.need_reinit = false;
	        return true;
	    }
	    return false;
    }, //reinit

    fetch_default_app:function() {
	    return this.default_app || this.fetch_root();
    },

    fetch_account:function() {
	    if( this.default_app ) {
	        if( ! this.acct_obj ) {
		        this.acct_obj = this.default_app.account();
	        }
	        return this.acct_obj;
	    }
	    return undefined;
    },

    fetch_app:function(appname,passhandler,failhandler) {
	    var yote_root = this.fetch_default_app();
	    if( typeof yote_root === 'object' ) {
	        var ret = yote_root.fetch_app_by_class( appname );
	        ret._app_id = ret.id;
	        return ret;
	    } else if( typeof failhanlder === 'function' ) {
	        failhandler('lost connection to yote server');
	    } else {
	        _error('lost connection to yote server');
	    }
    }, //fetch_app

    fetch_root:function() {
	    var r = $.yote.yote_root;
	    if( ! r ) {
	        r = this.message( {
		        async:false,
		        cmd:'fetch_root'
	        } );
	        $.yote.yote_root = r;
	    }
	    return r;
    }, //fetch_root

    // return not only root but login if applicable
    // returns root, app, login, account
    fetch_initial:function( token, appname ) {
	    if( r && typeof r === 'object' && r.length() > 2 ) {
	        return [ r.get(0), r.get(1), r.get(2), r.get(3) ];
	    }
    }, //fetch_initial

    get_by_id:function( id ) {
	    return $.yote.objs[id+''] || $.yote.fetch_default_app().fetch(id).get(0);
    },

    has_root_permissions:function() {
	    return this.is_logged_in() && 1*this.get_login().get_is_root();
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
	    $.yote.default_app = undefined;
	    $.yote.token = 0;
	    $.yote._dump_cache();
	    $.cookie( 'yoken', '', { path : '/' } );
    }, //logout

    /* general functions */
    message:function( params ) {
        var root   = this;
        var data   = root._translate_data( params.data || {} );
        var async  = params.async == true ? 1 : 0;
        var url    = params.url;
        var app_id = params.app_id || '';
        var cmd    = params.cmd;
        var obj_id = params.obj_id || ''; //id to act on

	    root.upload_count = 0;

	    if( ! app_id ) app_id = $.yote._app_id || 0;
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
        var get_data = $.yote.token + "/" + $.yote.guest_token;
	    var resp;

        if( $.yote.debug == true ) {
	        console.log("\noutgoing : " + cmd + '  : ' + url + '/' + get_data + '-------------------------' );
	        console.log( data );
	    }

	    $.ajax( {
	        async:async,
	        cache: false,
	        contentType: "application/json; charset=utf-8",
	        data : encoded_data,
	        dataFilter:function(a,b) {
		        if( $.yote.debug == true ) {
                    console.log( 'raw incoming ' );
                    var len = 160;
                    for( var i=0; i<a.length; i+=len ) {
                        console.log( a.substring( i, i+len ) );
                    }
                    // print out eadch substring on a line
                }
		        return a;
	        },

	        error:function(a,b,c) {
                root._error(a);
            },
	        success:function( data ) {
		        if( $.yote.debug == true ) {
                    console.log( ['incoming ', data ] );
                }
                if( typeof data !== 'undefined' ) {
		            resp = ''; //for returning synchronous

		            if( typeof data.err === 'undefined' ) {
			            //dirty objects that may need a refresh
                        $.yote.has_updated = false;
			            if( typeof data.d === 'object' ) {
                            $.yote.has_updated = true;
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
			            console.log( data.err );
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
			            console.log([ 'incoming ', resp ] );
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

    _wrap_list:function( obj, field, key ) {
        return $.yote._data_wrapper( obj, field, key );
    }, //wrap_list

    _wrap_hash:function( obj, field, key ) {
        return $.yote._data_wrapper( obj, field, key, true );
    }, //wrap_hash

    _data_wrapper:function( obj, field, key, is_hash ) {
        var node = is_hash ? $.yote._pag_hash_cache[ key ] : $.yote._pag_list_cache[ key ];
        if( ! key || (! node && ( (! obj && ! field ) ) ) ) {
            if( is_hash )
                throw new Exception( 'wrap hash called without ' + ( key ? 'hash' : 'key' ) );
            else
                throw new Exception( 'wrap list called without ' + ( key ? 'list' : 'key' ) );
        }

        if( ! node ) {
            var full_size = obj.count( { name : field } );
            var server_paginate = field.match( /^_/ ) || full_size > 300;

            var start = 0;
            node = {
                _server_paginate : server_paginate,
                _start : start,
                _data_size : full_size,
                _page_size  : 0,
                _filter_function     : undefined,
                _sort_function       : undefined,
                _transform_function  : undefined,
                set_filter : function( filter_fun ) {
                    this._filter_function = filter_fun;
                },
                set_sort : function( sort_fun ) {
                    this._sort_function = sort_fun;
                },
                set_transform : function( trans_fun ) {
                    this._transform_function = trans_fun;
                },
                back:function(){
                    this._start -= this._page_size;
                    if( this._start < 0 ) {
                        this._start = 0;
                    }
                },
                can_rewind:function(){
                    return this._start > 0;
                },
                can_fast_forward:function(){
                    return (this._start + this._page_size) < this._data_size;
                },
                forwards:function(){
                    this._start += this._page_size;
                    if( this._start >= this._data_size ) {
                        this._start = this._data_size - 1;
                    }
                },
                first:function(){
                    this._start = 0;
                },
                last:function(){
                    this._start = this._data_size - this._page_size;
                    if( this._start < 0 ) {
                        this._start = 0;
                    }
                },
                set_size : function( newsize ) {
                    this._page_size = Number(newsize);
                },
                to_list : function() {
                    var ret;
                    if( this._server_paginate ) {
                        ret = this._obj.paginate( { name : this._field } ).to_list();
                        //TODO : make this paginate for the filters rather than grabbing all
                    } else {
                        var o = this._obj.get( this._field );
                        ret = o ? o.to_list() : [];
                    }
                    if( typeof this._filter_function !== 'undefined' ) {
                        ret = this._arry.map( this._filter_function );
                    }
                    if( typeof this._sort_function !== 'undefined' ) {
                        ret = ret.sort( this._sort_function );
                    }
                    if( typeof this._start !== 'undefined' || typeof this._page_size !== 'undefined' ) {
                        if( typeof this._page_size !== 'undefined' )
                            ret = ret.slice( this._start, this._start + this._page_size );
                        else
                            ret = ret.slice( this._start );
                    }
                    return ret;
                },
                keys : function() {
                    var _hash;
                    if( this._server_paginate ) {
                        _hash = this._obj.paginate( { name : this._field, return_hash : 1 } ).to_hash();
                    } else {
                        var o = this._obj.get( this._field )
                        _hash = o ? o.to_hash() : {};
                    }
                    var ret = Object.keys( _hash );
                    if( typeof this._filter_function !== 'undefined' ) {
                        var new_ret = [];
                        for( var i=0; i<ret.length; i++ ) {
                            var k = ret[ i ];
                            if( this._filter_function( k, _hash[ k ] ) )
                                new_ret.push( k );
                        }
                        ret = new_ret;
                    }
                    ret = ret.sort( this._sort_function );
                    if( typeof this._start !== 'undefined' || typeof this._page_size !== 'undefined' ) {
                        if( typeof this._page_size !== 'undefined' )
                            ret = ret.slice( this._start, this._start + this._page_size );
                        else
                            ret = ret.slice( this._start );
                    }
                    return ret;
                },
                to_hash : function() {
                    var h;
                    if( this._server_paginate ) {
                        h = this._obj.paginate( { name : this._field, return_hash : 1 } ).to_hash();
                    } else {
                        var o = this._obj.get( this._field );
                        h = o ? o.to_hash() : {};
                    }
                    var r = {};
                    var k = this.keys();
                    for( var i=0; i<k.length; i++ ) {
                        r[ k[i] ] = h[ k[i] ];
                    }
                    return r;
                }
            };
            if( is_hash ) {
                $.yote._pag_hash_cache[ key ] = node;
            } else {
                $.yote._pag_list_cache[ key ] = node;
            }
        } else if( node.server_paginate ) {
            node._data_size = obj.count( { name : field } );
        } else {
            node._data_size = is_hash ? Object.count( node._obj.get( node._field ).to_hash() ) : node._obj.get( node._field ).to_list().length;
        }
        if( obj && field ) {
            node._obj = obj;
            node._field = field;
        }
        return node;
    }, //data_wrapper


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
				                    passhandler:passhandler
				                } ); //sending message
			                } } )(x.m[m],x);
		            } //each method
		        } // if methods were included in the return value of the call
	        } // if object

	        o.get = function( key ) {
		        var val = this._staged[key] || this._d[key];
		        if( typeof val === 'undefined' ) return undefined;
		        if( typeof val === 'object' ) return val;
		        if( typeof val === 'function' ) return val;

		        if( val.substring(0,1) != 'v' ) {
		            var obj = root.objs[val+''];
		            if( ! obj ) {
			            var ret = $.yote.fetch_default_app().fetch(val);
			            if( ! ret ) return undefined; //this can happen if an authorized user logs out
			            obj = ret.get(0);
		            }
		            obj._app_id = this._app_id;
                    return obj;
		        }
		        var ret = val.substring(1);
                return typeof ret * 1 !== 'NaN' ? ret : ret * 1;
	        };

	        o.is = function( othero ) {
		        var k = this.id;
		        var ok = othero ? othero.id : undefined;
		        return k !== 'undefined' && k == ok;
	        }

	        o._get_id = function( key ) {
		        // returns the id ( if any of the item specified by the key )
		        var val = this._d[key];
		        return val && val.substring(0,1) != 'v' ? val : undefined;
	        },

	        o.set = function( key, val, failh, passh ) {
		        this._stage( key, val );
		        this._send_update( undefined, failh, passh );
		        delete this._staged[ key ];
                if( ! this[ 'set_' + key ] )
                    this[ 'set_' + key ] = (function(k) { return function(val,fh,ph) { return this.set(k,val,fh,ph) } } )(key);
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
                    app_id:$.yote._app_id,
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
            $("*").css("cursor", "wait");
            this.enabled = $(':enabled');
	        $.each( this.enabled, function(idx,val) { val.disabled = true; } );
	    }
    }, //_disable

    _dump_cache:function() {
        this.objs = {};
	    this.apps = {};
	    this.yote_root   = undefined;
	    this.default_app = undefined;
        this._app_id = undefined;
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
        $("*").css("cursor", "auto");
        $.each( this.enabled, function(idx,val) { val.disabled = false } );
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


# ----------------- END OF YOTE SPECIFIC CODE -------------------------


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
if( ! Object.clone ) {
    // shallow clone
    Object.clone = function( h ) {
        var clone = {};
        for( var key in h ) {
	        clone[ key ] = h[ key ];
        }
        return clone;
    }
}
