var yote = {}; // yote var

/*
   yote.init - sets up contact with the yote server and runs a handler provided, passing it
               the server root object and optionally an app object.

   usage :

      yote.init( {

         yoteServerUrl : 'optional. include only if yote server is different than the server that served this js doc',
 
         appName : 'optional. If given, then an app object is also passed to the handler.',

         handler : function( root, app ) { // app is only passed in if appName is an argument
            // do stuff
         },

         errHandler : function(err) { } //optional
      } );

    The app and root objects are yote objects.


    A note on yote methods :
      yote methods are called with an array of parameters, a success handler and a fail handler
      all are optional, but the first function encounted is going to be the success handler. The
      next the fail handler. Passing in a single argument is also allowed :
      So the method signatures are as follows :

    yoteobj.doSomething( [arg1,arg2,..], successHandler, failHandler );
    yoteobj.doSomething( [arg1,arg2,..], successHandler );
    yoteobj.doSomething( singlearg, successHandler, failHandler );
    yoteobj.doSomething( singlearg, successHandler );
    yoteobj.doSomething( successHandler, failHandler );
    yoteobj.doSomething( successHandler );


*/
yote.init = function( args ) {

    var yoteServerURL = args.yoteServerURL || '';

    var token, root, app, appname, acct;


    token = localStorage.getItem('token');
    
    // cache storing objects and their meta-data
    var class2meths = {};

    var id2obj = {};
    

    var _register = function( id, obj ) {
        id2obj[ id ] = obj;
        console.log( [ "REGGY " + id, obj._data ] );
        localStorage.setItem( id, JSON.stringify( {
            id    : obj.id,
            _cls  : obj._cls,
            _data : obj._data,
            _meths : obj._meths
        } ) );
    }


    // creates a proxy method that contacts the server and
    // returns data
    function makeMethod( mName ) {
        var nm = '' + mName;
        return function( data, handler, failhandler ) {
            var that = this;
            var id = this.id;

            if( typeof data === 'function' ) {
                failhandler = handler;
                handler = data;
                data = [];
            } else if( ! Array.isArray( data ) ) {
                // TODO - maybe detect if there are non-functions in the arguments list? gather into array all non-function args
                // like so
                data = [data];
            }

            var res = contact( id, nm, data, handler, failhandler );
        };
    };

    var makeObjSkell = function( cls ) {
        var obj = {
            _cls  : cls,
            _data : {},
            listeners : {},
            
            // takes a function that takes this object as a
            // parameter
            addUpdateListener : function( listener, key ) {
                key = key || '_';
                if( key === '_' ) {
                    var defs = this.listeners[ key ];
                    if( ! defs ) {
                        defs = [];
                        this.listeners[ key ] = defs;
                    }
                    defs.push( listener );
                } else {
                    this.listeners[ key ] = listener;
                }
                return this;
            },
            removeUpdateListeners : function( key ) {
                if( key ) {
                    delete this.listeners[ key ];
                } else {
                    this.listeners = {};
                }
                return this;
            },
            get : function( key ) {
                var val = this._data[key];
                if( typeof val === 'undefined' || val === null ) {
                    return undefined;
                }
                if( typeof val === 'string' && val.startsWith( 'v' ) ) {
                    return val.substring( 1 );
                } 
                return yote.fetch( val );
            }
        };

        if( cls === 'ARRAY' ) {
            obj.toArray = function() {
                var a = [];
                for( var k in obj._data ) {
                    a[k] = obj.get( k );
                }
                return a;
            };
            obj.each = function( fun ) {
                for( var k in obj._data ) {
                    fun( obj.get( k ), k );
                }
            };
            obj.length = function() {
                return Object.keys( obj._data ).length;
            };
        }
        var mnames = class2meths[ cls ] || [];
        obj._meths = mnames;
        mnames.forEach( function( mname ) {
            obj[ mname ] = makeMethod( mname );
        } );
        return obj;
    }; //makeObjSkell
    
    // returns an object, either the cache or server
    var _fetch = function( id ) {
        if( id2obj[id] ) {
            return id2obj[id];
        }
        var objdata = JSON.parse( localStorage.getItem( id ) );
        if( ! objdata ) {
            return null;
        }
        var obj = makeObjSkell( objdata._cls );
        obj._data = objdata._data;
        obj.id = id;
        id2obj[id] = obj;
        
        return obj;
    }; //_fetch

    yote.fetch = _fetch;
    
    // method for translating and storing the objects
    // NOTE : returns a function used for updating
    function makeObj( datastructure ) {
        /* method that returns the value of the given field on the yote obj */
        var obj = _fetch( datastructure.id );
        var isUpdate = obj !== null && typeof obj === 'object';
        // TODO : maybe include what was updated and pass that to the action listener?
        if( ! isUpdate ) {
            obj = makeObjSkell( datastructure.cls );
            obj.id = datastructure.id;
            obj._data = datastructure.data;
        }
        console.log( [ "MAKE OBJ " + datastructure.id, obj, obj._data ] );
        obj._data = datastructure.data;
        _register( datastructure.id, obj );
        
        // fire off an event for any update listeners
        return function() {
            if( isUpdate ) {
                for( var key in obj.listeners ) {
                    if( key === '_' ) {
                        obj.listeners[key].forEach( function( l ) {
                            l( obj );
                        } );
                    } else {
                        obj.listeners[key]( obj );
                    }
                };
            }
        }
    } //makeObj
    
    function processReturn( returnData ) {
        if( Array.isArray( returnData ) ) {
            var ret = returnData.map( function( x ) {
                return processReturn( x );
            } );
            return ret;
        } 
        else if( typeof returnData === 'object' ) {
            var ret = {};
            for( var k in returnData ) {
                ret[k] = processReturn( returnData[k] );
            }
            return ret;
        } 
        else if( typeof returnData === 'string' && returnData.startsWith('v') ) {
            return returnData.substring(1);
        }
        else if( returnData ) {    
            return yote.fetch( returnData );
        }
    } //processReturn

    function processRaw(rawResponse,succHandle,failHandle) {
        var res = JSON.parse( rawResponse );

        // check for errors
        if( res.err ) {
            if( failHandle ) {
                failHandle( res.err );
            }
            return;
        }
        
        // ** 3 parts : methods, updates and result
        
        // methods
        if( res.methods ) {
            for( var cls in res.methods ) {
                class2meths[cls] = res.methods[ cls ];
            }
        }
        
        // updates
        if( res.updates ) {
            var makeOrUpdateFuns = [];
            res.updates.forEach( function( upd ) {
                if( typeof upd !== 'object' || ! upd.id ) {
                    console.warn( "Update error, was expecting object, not : '" + upd + "'" );
                } else {
                    // good place for an update listener
                    makeOrUpdateFuns.push( makeObj( upd ) );
                }
            } ); //updates section
            makeOrUpdateFuns.map( function( fun ) {
                fun();
            } );
        }
        
        // results
        if( res.result && succHandle ) {
            var resses = processReturn( res.result );
            var finalRes = resses.length > 1 ? resses : resses[0];
            succHandle( finalRes );
        }
    }; //processRaw

    // yote objects can be stored here, and interpreting
    // etc can be done here, the get & stuff
    function reqListener( succHandl, failHandl ) { 
        return function() {
            console.log( "GOT FROM SERVER : " + this.response );
            if( typeof this === 'object' ) {
                processRaw( this.response, succHandl, failHandl );
            } else if( failHandl ) {
                failHandl( 'failed' );
            }
        };
    };

    function readyObjForContact( obj ) {
        if( typeof obj !== 'object' ) {
            return typeof obj === 'undefined' || obj === null ? undefined : 'v' + obj;
        }
        if( _fetch( obj.id ) === obj ) {
            return obj.id;
        }

        for( var idx in obj ) {
            var v = obj[idx];
            if( typeof v === 'object' ) {
                if( _fetch( v.id ) === v ) {
                    v = v.id;
                } else {
                    v = readyObjForContact( v );
                }
            } else {
                v = 'v' + v;
            }
            obj[idx] = v;
        }
        return obj;
    }

    function contact(id,action,data,handl,errhandl) { 
        var oReq = new XMLHttpRequest();
        oReq.addEventListener("loadend", reqListener( handl, errhandl ) );
        oReq.addEventListener("error", function(e) { alert('error : ' + e) } );
        oReq.addEventListener("abort", function(e) { alert('abort : ' + e) } );

        console.log( "CONTACTING SERVER ASYNC via url : " + yoteServerURL + 
                     '/' + id +
                     '/' + ( token ? token : '_' ) + 
                     '/' + action )
        
        oReq.open("POST", yoteServerURL, true );

        var readiedData = typeof data === 'undefined' || data === null ? undefined : readyObjForContact( data );

        // for a single parameter, wrap into a parameter list
        var sendData = 'p=' + JSON.stringify( { pl    : readiedData, //payload
                                                i     : id,                 
                                                t     : token ? token : '_',
                                                a     : action
                                              } );

        
        console.log( "About to send to server : " + sendData );

        // data must always be an array, though that array may have different data structures inside of it
        // as vehicles for data
        oReq.setRequestHeader("Content-type", "application/x-www-form-urlencoded" );
        oReq.send( sendData );

    }; // contact
   // translates text to objects
    function xform_in( item ) {
        if( typeof item === 'object' ) {
            if( item === null ) {
                return undefined;
            }
            if( Array.isArray( item ) ) {
                return item.map( function( x ) { return xform_in(x); } );
            } else {
                var ret = {};
                for( var k in item ) {
                    ret[ k ] = xform_in( item[k] );
                }
                return ret;
            }
        } else {
            if( typeof item === 'undefined' || item === null ) return undefined;
            if( typeof item === 'string' && item.startsWith('v') ) {
                return item.substring( 1 );
            } else {
                return _fetch( item );
            }
        }
    }
    

    // transform from objects to text
    function xform_out( res ) {
        if( typeof res === 'object' ) {
            if( Array.isArray( res ) ) {
                return res.map( function( x ) { return xform_out( x ) } );
            }
            var obj = _fetch( res.id );
            if( obj ) { return res.id }
            var ret = {};
            for( var key in res ) {
                ret[key] = xform_out( res[key] );
            }
            return ret;
            
        }
        if( typeof res === 'undefined' ) return undefined;
        return 'v' + res;
    }//xform_out

    appname = args.appName;
    var handler = args.handler;
    var errhandler = args.errHandler;

    if( ! handler ) {
        console.warn( "Warning : yote.init called without handler" );
    }
    contact( '_', 'init_root', [], function(res) {
        root  = res[0];
        token = res[1];
        localStorage.setItem( 'token', token );

        if( handler ) {
            if( appname ) {
                root.fetch_app( [appname], function( result ) {
                    if( Array.isArray( result ) ) {
                        console.log( [ result,"RESSY" ] );
                        app = result[0];
                        acct = result[1];
                    } else {
                        app = result;
                    }
                    handler( root, app, acct );
                } );
            } else {
                handler( root );
            }
        }
    }, errhandler );

    yote.logout = function( handler ) {
        if( app ) {
            app.logout(function() {
                localStorage.clear();

                acct = undefined;
                token = undefined;
                app = undefined;

                contact( '_', 'init_root', [], function(res) {
                    root  = res[0];
                    token = res[1];
                    localStorage.setItem( 'token', token );

                    if( appname ) {
                        root.fetch_app( [appname], function( result ) {
                            if( Array.isArray( result ) ) {
                                app = result[0];
                            } else {
                                app = result;                                
                            }
                            if( handler ) {
                                handler( root, app );
                            }
                        } );
                    } else if( handler ) {
                        handler( root );
                    }
                }, errhandler );

            }, function(err) { localStorage.clear(); } );
        } else {
            localStorage.clear();
        }
    } //yote.logout
    
}; //yote.init

yote.sameyoteobjects = function( a, b ) {
    return typeof a === 'object' && typeof b === 'object' && a.id === b.id;
};
