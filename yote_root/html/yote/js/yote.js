/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Version 0.3
 */

/*
debug,token,objs,_dump_cache,_cache_size,_debug_[sg]et_message

init
logout
reinint
fetch_app
fetch_root
login

  $.yote.upload
  $.yote.upload_message
*/
if( ! window.$ ) {
    window.$ = {};
}

/*
  Upon script load, see if a port was explicity given in the script
  tag calling this file. If there is a port specified, use that
  location as an absolute location when making the yote ajax calls. 
  If the normal port is used, that means the script is called from the 
  same place as the page and relative urls can be used for the ajax calls.
*/
var scripts = document.getElementsByTagName('script');
var myScriptUrl = scripts[scripts.length - 1].src;
var ma = myScriptUrl.match( /^((https?:\/\/)?[^\/]+(:(\d+))?)\// );

var _url = ma && ma.length > 1 ? ma[ 1 ] : ''; // domain/port to use for message calls

var _debug = false;
 
var _yote_root, _default_app, _default_appname, _app_id;
var _guest_token, _auth_token = $.cookie('yoken');
var _login_obj, _acct_obj;

/*
  Yote API :
    $.yote._get_message_function
    $.yote._set_message_function

    $.yote.init
    $.yote.fetch_root - get the master root object from which account stuff can be done
*/

/*
            ----------- CACHING --------
 */
var _object_cache = {};


/*
            ----------- DATA FUNCTIONS --------
 */

var _encode_data = function(data) {
    // returns a base 64 encoded version of the data for io transfer
    return $.base64.encode( JSON.stringify( { d : _prepare_data(data) } ) );
};
var _untranslate_data = function(data) {
    // returns the object or string the data represents
    return data.substring(0,1) == 'v' ? data.substring(1) : _object_cache[ data ];
};
var _prepare_data = function(data) {

    // takes a data structure and converts all non-null, non-objects to the yote 'v' + value format.
    // translates all yote objects to their ids
    // for non-yote lists and hashes, it prepares their data recursively
    // TODO : check for recursive data structures
    if( typeof data === 'undefined' ) {
        return undefined;
    }
    if( typeof data !== 'object' ) {
        // string value
        return 'v' + data;
    }
    else if( data._id ) { 
        // yote object
        return data._id;
    }

    // now the case that parameters are being sent through,
    // list a hash or parameters or a list of things but that list does not get created
    var ret = $.isArray( data ) ? [] : {};
    for( var key in data ) {
        ret[key] = _prepare_data( data[key] );
    }
    return ret;
}; //_prepare_data


/*
            ----------- IO FUNCTIONS --------
 */
var _message = function( params ) {
    // sends a post request to the yote server. 
    // the data is a base64 encoded json blob
    _handle_event( 'message_start', params );

    var outgoing_data   = _encode_data( params.data );

    var async  = params.async == true ? 1 : 0;
    var url    = params.url;
    var app_id = params.app_id || _app_id || 0;
    var cmd    = params.cmd;
    var obj_id = params.obj_id || 0; //id to act on

    var url = _url + '/_/' + app_id + '/' + obj_id + '/' + cmd;

    var get_data = _auth_token + "/" + _guest_token;
	var resp;

    if( _debug ) {
        // TODO : have this a debug event rather than just a console log
	    console.log("\noutgoing : " + cmd + '  : ' + url + '/' + get_data + '-------------------------' );
	    console.log( outgoing_data ); 
	}

	$.ajax( {
	    'async':async,
	    'cache': false,
	    'contentType': "application/json; charset=utf-8",
	    'data' : outgoing_data,
	    'dataFilter':function(a,b) {
		    if( _debug ) {         // TODO : have this a debug event rather than just a console log
                console.log( 'raw incoming ' );
                var len = 160;
                for( var i=0; i<a.length; i+=len ) {
                    console.log( a.substring( i, i+len ) );
                }
                // print out eadch substring on a line
            }
		    return a;
	    },
	    'error':function(a,b,c) { 
            _handle_event( 'error', a );
            if( async ) {
                _handle_event( 'message_fail', params );
                _handle_event( 'message_complete', params );
            }
        },
	    'success':function( incoming_data ) {
		    if( _debug ) {        // TODO : have this a debug event rather than just a console log
                console.log( ['incoming ', incoming_data ] );
            }
            if( typeof incoming_data !== 'undefined' ) {
		        resp = ''; //for returning synchronous messages
		        if( typeof incoming_data.err === 'undefined' ) {
			        if( typeof incoming_data.d === 'object' ) {
                        // incoming_data.d is a list of object ids that need to be refreshed if they have been cached.
			            for( var oid in incoming_data.d ) {
				            var cached = _object_cache[ oid ];
                            if( cached ) {
                                cached._reset( incoming_data.d[ oid ] );
				            }
			            } //each dirty
			        } //if dirty

                    resp = typeof incoming_data.r === 'object' ? _create_object( incoming_data.r, app_id ) : 
                        incoming_data.r ? incoming_data.r.substring( 1 ) : undefined;

		            typeof params.passhandler === 'function' && params.passhandler( resp );

		        } //no error 
                else if( typeof params.failhandler === 'function' ) {
                    _handle_event( 'error', incoming_data.err );
		            params.failhandler(incoming_data.err);
                } //error case. no handler defined
            } else {
                // TODO : have this a debug event rather than just a console log
                console.log( "Success reported but no response data received. Some server side goofiness" );
            }
            if( async ) {
                _handle_event( 'message_success', params );
                _handle_event( 'message_complete', params );
            }

	    },
	    'type':'POST',
	    'url':url + '/' + get_data
	} );
    
    if( ! async ) {
        _handle_event( 'message_success', params );
        _handle_event( 'message_complete', params );
        return resp;
    }
}; //_message

var _is_in_cache = function( id ) {
    return _object_cache[id] != null;
}


//data.id
//data.c  -class
//data.m  -methods
//data.d  -property hash

/*
  methods on the object :
   * length
   * equals
   * keys
   * values
   * sort
   * to_hash/to_list/all method names defined from data
   * get
   * is
   * set
   * data defined getters and setters
   * _reset
   * _is_dirty
   * _send_update
*/
var _create_object = function( data, app_id ) {
    
    var _obj_class   = data.c;
    var _id          = data.id;
    var _app_id      = app_id;

    var _imported_methods = data.m || [];
    var _imported_data = data.d || {};

    var _stored_data = {};
    var _staged_data = {};

    var _length = function() {
        return Object.keys( _stored_data ).length;
    };

    var _send_update = function( data, on_fail, on_pass ) {
        var send_data = data || _staged_data || {};
        var staged_keys = Object.keys( send_data );

        if( staged_keys.length == 0 ) {
            return;
        }
        var to_send;
        if( data ) {
            if( _obj_class === 'Array') {
                to_send = data;
            } else {
                to_send = {};
                staged_keys.map( function( key ) { to_send[key] = data[ key]; } );
            }
        } else {
            if( _obj_class === 'Array') {
                to_send = staged_keys.map( function( key ) { return _untranslate_data( send_data[ key ] ); } );
            } else {
                to_send = {};
                staged_keys.map( function( key ) { to_send[key] = _untranslate_data( send_data[ key ] ); } );
            }
        }

        var to_send;
        _message( {
            'app_id' : _app_id,
            'async'  : false,
            'data'   : to_send,
            'cmd'    : 'update',
            'failhandler' : function() {
                if( on_fail ) {
                    on_fail();
                }
            },
            'obj_id' : _id,
            'passhandler' : function() {
                if( on_pass ) {
                    on_pass();
                }
            }
        });
    }; //_send_update

    var _set = function( key, val, fail_handler, pass_handler ) {
        this._stage( key, val );
        _send_update( undefined, fail_handler, pass_handler );
        delete _staged_data[ key ];
        if( ! obj[ 'set_' + key ] ) {
            obj[ 'set_' + key ] = function( newval, on_fail, on_pass ) {
                return _set( key, newval, on_fail || fail_handler, on_pass || pass_handler );
            }
        }
    }; //_set
    

    var _get = function( key ) {
        var val = typeof _staged_data[ key ] != 'undefined'  ? _staged_data[ key ] : _stored_data[ key ];
        var val_type = typeof val;
        if( val_type === 'undefined' || val_type === 'object' || val_type === 'function' ) {
            return val;
        }
		if( val.substring(0,1) != 'v' ) {
		    var obj = _object_cache[ val ];
		    if( ! obj ) {
			    var ret = _default_app ? _default_app.fetch(val) : undefined;
			    if( ! ret ) return undefined; //this can happen if an authorized user logs out
			    obj = ret._get(0);
		    }
		    obj._set_app_id( _app_id );
            return obj;
		}

        // 'scalar' value
		var ret = val.substring(1);
        // if the return value could be a number, return it as such
        return Number.isNaN( Number( ret ) ) ? ret : Number( ret );
    }; //_get

    var obj = {
        '_id'      : _id,
        '_app_id'  : _app_id,
        '_get'     : _get,
        '_set_app_id' : function( app_id ) { _app_id = app_id; },
        '_send_update' : _send_update,
        '_stored_data' : _stored_data,
        '_obj_class' : _obj_class,
        'length'  : _length,
        'equals'  : function(oth) {
            return typeof oth === 'object' && oth._id == _id;
        },
        'is'      : function(oth) {
            return _id && typeof oth === 'object' && oth._id == _id;
        },
        'get' : _get,
        'set' : _set,
        '_reset'  : function( field )  {
            if( typeof field === 'object' ) {
                for( fld in _stored_data ) {
                    delete _stored_data[ fld ];
                    delete _staged_data[ fld ];
                    delete this[ 'get_' + fld ];
                }
                for( fld in field ) {
                    _stored_data[ fld ] = field[fld];
                    this[ 'get_' + fld ] = (function(f) { return function() { return _get( f ); } })(fld);
                }
            }
            else if( typeof field === 'string' ) {
                delete _staged_data[ field ];
            } else {
                _staged_data = {};
            }
        },
        '_stage' : function( key, val ) {
            var tr = _prepare_data( val );
            if( _staged_data[ key ] !== tr ) {
                _staged_data[ key ] = tr;
                _dirty = true;
            }
        },
        'keys'   : function() {
            return Object.keys( _stored_data );
        },
        'values' : function() {
            var that = this;
            return Object.keys( _stored_data ).map(function(key) { return _get( key ); } );
        },
        'sort'   : function(sortfun) {
            return this.values().sort( sortfun );
        }
    };
    if( _id ) {
        _object_cache[ _id ] = obj;
    }
    if( _obj_class === 'HASH' ) {
        obj.to_hash = function() {
            return Object.keys( _stored_data ).map(function(key) { return _get( key ); } );
        };
    } 
    else if( _obj_class === 'ARRAY' ) {
        obj.to_list = function() {
            var list = [];
            for( var i=0, len = _length(); i < len; i++ ) {
                list[ i ] = _get( i );
            }
            return list;
        };
    } 
    else { // yote objects with yote object methods and get/set methods
        _imported_methods.map( function( method_name ) {
            obj[ method_name ] = function( params, passhandler, failhandler, use_async ) {
                return _message( {
				    'async'   : use_async ? true : false,
				    'app_id'  : _app_id,
				    'cmd'     : method_name + '', //closurify
				    'data'    : params,
				    'failhandler' : failhandler,
                    'obj_id'  : obj._id,
				    'passhandler' : passhandler
                } );
            };
        } );
    } // yote obj
    Object.keys( _imported_data ).map( function( field ) {
        obj[ 'get_' + field ] = (function(fld) { return function() { 
            return _get( fld ); 
        }; } )( field );
        obj[ 'set_' + field ] = (function(fld) { return function(value,fh,ph) { 
            return _get( fld ); 
        }; } )( field );
        var val = _imported_data[ field ];
        if( typeof val === 'object' && val != null ) {
            _stored_data[ field ] = (function(v) { return _create_object( v, app_id ); })(val);
        }
        else {
            _stored_data[ field ] = (function(v) { return v; } )( val );
        }
        
    } );


    return obj;
}; //_create_object

/*
     ------------------------ AUTHENTICATION ------------------
*/
var _authenticate = function() {
    
}; //_authenticate


/*
            ----------- EVENT HANDLERS --------
 */
var _event_handlers = {
    'error' : [ 
        function( event ) {
            console.log( ["a server side error has occurred", event ] );
        } ],
    'debug' : [
        function( event ) {
            console.log( event );
        }
    ]
}; //_event_handlers
var _handle_event = function( event_type, event ) {
    var handlers = _event_handlers[ event_type ];
    if( handlers ) {
        handlers.forEach( function( handler ) { handler( event ); } );
    }
}; //_handle_event

var util = ( window.$ && window.$.yote ? window.$.yote.util : {} ) || {};

window.$.yote = {
    'util' : util,
    '_get_message_function' : function() { return _message; },
    '_set_message_function' : function(newf) { _message = newf; return this; },
    '_get_token' : function() { return _auth_token; },
    '_object_cache' : function() { return _object_cache; },
    '_cache_size' : function() { return Object.keys(_object_cache).length; },
    '_login_obj' : function() { return _login_obj; },

    'init' : function(appname) {
        var ret;
        _message( {
	        async:false,
	        cmd:'fetch_initial',
	        data:{ t:_auth_token || _guest_token,
                   a:appname },
	        passhandler:function( initial_data ) {	    
		        if( typeof initial_data === 'object' && initial_data._get( 'root' ) && initial_data._get( 'app' ) ) {
		            _yote_root = initial_data._get( 'root' ); 
                    _yote_root._app_id = _yote_root.id;

		            _object_cache[ _yote_root._id ] = _yote_root;

		            var app = initial_data._get( 'app' ) || _yote_root;
		            app._app_id = app.id;
		            _app_id = app.id;
		            _default_app = app;
		            _default_appname = appname;
		            _object_cache[ app._id ] = app;
                    _login_obj   = initial_data._get(  'login' );
		            _acct_obj    = initial_data._get(  'account' );
                    _acct_obj._app_id = app.id;

		            _guest_token = initial_data._get(  'guest_token' );

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

    'reinit' : function( token ) {
	    if( ! _default_app ) {
	        this.init( _default_appname, token );
	        return true;
	    }
	    return false;
    }, //reinit

    'fetch_app' : function( appname,passhandler,failhandler ) {
        this.fetch_root( passhandler, failhandler );
        var ret = _yote_root.fetch_app_by_class( appname, passhandler, failhandler );
        ret._app_id = ret.id;
        
        return ret;
    }, //fetch_app
    
    'fetch_default_app' : function() {
        return _default_app;
    }, // fetch_default_app

    'fetch_root' : function(passhandler,failhandler) {
        if( ! _yote_root ) {
            _yote_root = _message( {
	            async:false,
	            cmd:'fetch_root',
                passhandler : passhandler,
                failhandler : failhandler
	        } );
            if( ! _default_app ) {
                _default_app = _yote_root;
            }
        }
        return _yote_root;
    },
    
    'login' : function( handle, password, passhandler, failhandler ) {
	    var root = this.fetch_root();
	    if( typeof root === 'object' ) {
	        root.login( { h:handle, p:password },
			            function(res) {
			                _auth_token = res._get( 't' ) || 0;
			                _login_obj = res._get( 'l' );
			                $.cookie( 'yoken', _auth_token, { path : '/' } );
			                if( typeof passhandler === 'function' ) {
				                passhandler(res);
			                }
			            },
			            failhandler );
	        return _login_obj;
	    } else if( typeof failhanlder === 'function' ) {
	        failhandler('lost connection to yote server');
	    } else {
	        _error('lost connection to yote server');
	    }
    }, //login

    'fetch_account' : function() { return _acct_obj; },

    'logout' : function() {
	    $.yote.fetch_root().logout();
	    _login_obj = undefined;
	    _acct_obj = undefined;
	    _default_app = undefined;
	    _auth_token = 0;
	    $.yote._dump_cache();
	    $.cookie( 'yoken', '', { path : '/' } );
    },

    _dump_cache : function() {
        _object_cache = {};
        _default_app  = undefined;
        _yote_root    = undefined;
    },

/*
    // event handler. just has errors at first
    // TODO : how to remove these handlers
    'on' : function( event, handler ) { 
        if( !_event_handlers[ event ] ) { 
            _event_handlers[ event ] = []; 
        }
        _event_handlers[ event ].push( handler ); 
        return this; 
    }, //on
*/
    '_set_debug' : function( d ) { _debug = d; return this; },
    '_debug_cache_size' : function() { },
    '_debug_dump_cache' : function() { },
};



