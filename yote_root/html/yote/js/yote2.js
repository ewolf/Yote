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
var index = scripts.length - 1;
var myScriptUrl = scripts[index].src;
var ma = myScriptUrl.match( /^((https?:\/\/)?[^\/]+(:(\d+))?)\// );
var _url = ma && ma.length > 1 ? ma[ 1 ] : '';


var _debug = false;
var _app_id;

var _yote_root;
var _auth_token = $.cookie('yoken');
var _guest_token;

/*
  Yote API :
    $.yote._get_message_function
    $.yote._set_message_function

    $.yote.init
    $.yote.fetch_root - get the master root object from which account stuff can be done
*/


window.$.yote = {

    '_get_message_function' : function() { return _message; },
    '_set_message_function' : function(newf) { _message = newf; return this; },

    'init' : function( fun ) {
        _message( {
	        async:true,
	        cmd:'fetch_initial',
	        data:{ t:_auth_token || _guest_token,a:appname },
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

    'fetch_root' : function() {
        if( ! _yote_root ) {
        }
        return _yote_root;
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
    if( hanlders ) {
        _handlers.forEach( function( handler ) { handler( event ); } );
    }
}; //_handle_event

/*
            ----------- CACHING --------
 */
var _object_cache = {};


/*
            ----------- DATA FUNCTIONS --------
 */

var _translate_data = function(data) {
    // returns a base 64 encoded version of the data for io transfer
    return $.base64.encode( JSON.stringify( { d : _prepare_data(data) } ) );
}
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
    else if( data.id && _object_cache[ data.id ] === data ) {
        // yote object
        return data.id;
    }

    // now the case that parameters are being sent through,
    // list a hash or parameters or a list of things but that list does not get created
    var ret = $.isArray( data ) ? [] : {};
    for( var key in data ) {
        ret[key] = _prepare_data( data[key] );
    }
    return ret;
}, //_prepare_data


/*
            ----------- IO FUNCTIONS --------
 */
var _message = function( params ) {
    // sends a post request to the yote server. 
    // the data is a base64 encoded json blob
    _handle_event( 'message_start', params );

    var outgoing_data   = _translate_data( params.data );

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

                                // ASAP TODO : the yote objects on this side and give them a reset function
                                //             and have them use the damn prototypes or something.
                                //             maybe a function like _set_data( object, newdata )
				                for( fld in cached._d ) {
					                //take off old getters/setters
					                delete cached['get_'+fld];
				                }
				                cached._d = incoming_data.d[ oid ];

				                for( fld in cached._d ) {
					                //add new getters/setters
					                cached['get_'+fld] = (function(fl) { return function() { return this.get(fl) } } )(fld);
				                }
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
