var yote = {
    functions        : {},
    registerFunction : function( funname, fun ) {
        if( yote.functions[funname] ) {
            console.warn( "yote.registerFunction overriding '" + funname + "'" );
        }
        yote.functions[ funname ] = fun;
        return fun;
    }

}; // yote var

yote.expose = function() {
    // a no op, but this makes variables visible from worker to
    // main thread
}

yote.initMain = function( yoteServerURL ) {
    yote._init( yoteServerURL, false );
//    yote._findControls();
}; //initWorker

yote.initWorker = function( yoteServerURL ) {
    yote._init( yoteServerURL, true );
}; //initWorker

yote._init = function( yoteServerURL, isWorker ) {

    isWorker = isWorker ? true : false; // can't be undefined or things like that
    workerTxt = isWorker ? "ISWORKER" : "NOTWORK";

    if( ! yoteServerURL ) { 
        yoteServerURL = '';
    }

    // cache storing objects and their meta-data
    var class2meths = {};
    var id2obj = {};
    yote.__object_library = id2obj;

    // returns an object, either the cache or server
    var fetch = function( id ) {
        if( isWorker ) {
            return id2obj[ id ] || yote.root.fetch( id );
        }
        var r = id2obj[ id ];
        if( typeof r === 'undefined' ) {
            console.warn( "warning : nonWorker fetching asynchronously" );
            r = yote.root.fetch( id );
        }
        return r;
    }
    yote.fetch = fetch;

    // creates a proxy method that contacts the server and
    // returns data
    var makeMethod = function( mName ) {
        var nm = '' + mName;
        return function( data, rawOrHandler, failhandler ) {
            var that = this;
            var id = this.id;
            
            if( isWorker ) { 
                if( typeof rawOrHandler === 'boolean') {
                    var useRaw = rawOrHandler;
                } else {
                    var sucHandler = rawOrHandler;
                }
                var res = contact( id, nm, data, useRaw, sucHandler );
                return res;
            } else {
                // here we contact the worker which passes
                // the request forwards
                yote.callWorker( {
                    callType  : 'method_call',
                    params      : [ that, nm, data || []],
                    callback    : typeof rawOrHandler === 'function' ? rawOrHandler : undefined,
                    failhandler : failhandler
                } );
            }
        };
    };

    var isObj = function( item ) {
        return typeof item === 'object' && id2obj[ item.id ];
    };

    // method for translating and storing the objects
    var makeObj = function( datastructure ) {
        /* method that returns the value of the given field on the yote obj */
        var obj = id2obj[ datastructure.id ];
        var isUpdate = typeof obj === 'object';
        if( ! isUpdate ) {
            obj = {};
            obj.id = datastructure.id;
            obj.listeners = {};
            id2obj[ datastructure.id ] = obj;
        }
        obj.cls = datastructure.cls;
        obj._data = datastructure.data;

        // takes a function that takes this object as a
        // parameter
        obj.addUpdateListener = function( listener, key ) {
            key += '';
            obj.listeners[ key ] = listener;
        }
        obj.get = function( key ) {
            var val = this._data[key];
            if( typeof val === 'undefined' ) {
                return undefined;
            }
            if( typeof val === 'string' && val.startsWith( 'v' ) ) {
                return val.substring( 1 );
            } 
            return fetch( val );
        };
        obj._is = function( other ) {
            return typeof other === 'object' && other.id === this.id;
        };
        obj._toData = function() {
            return { id  : this.id,
                     cls : this.cls,
                     data : this._data
                   };
        }; //ugh, case of a list returned?

        if( datastructure.cls === 'ARRAY' ) {
            obj.toArray = function() {
                var a = [];
                for( var k in obj._data ) {
                    a[k] = obj.get( k );
                }
                return a;
            }
            obj.length = function() {
                return Object.keys( obj._data ).length;
            }
        }
        
        var mnames = class2meths[ datastructure.cls ] || [];
        mnames.forEach( function( mname ) {
            obj[ mname ] = makeMethod( mname );
        } );

        // fire off an event for any update listeners
        if( isUpdate ) {
            var listens = obj.listeners;
            for( var k in listens ) {
                listens[k]( obj );
            };
        }

    } //makeObj
    
    var processRaw = function(rawResponse,expectAlist) {
        if( ! rawResponse ) {
            return;
        }
        var res = JSON.parse( rawResponse );
        
        // ** 3 parts : methods, updates and result
        
        // methods
        if( res.methods ) {
            for( var cls in res.methods ) {
                class2meths[cls] = res.methods[ cls ];
            }
        }
        
        // updates
        if( res.updates ) {
            res.updates.forEach( function( upd ) {
                if( typeof upd !== 'object' || ! upd.id ) {
                    console.error( "Update error [ " + workerTxt + "], was expecting object, not : '" + upd + "'" );
                } else {
                    // good place for an update listener
                    makeObj( upd );
                }
            } ); //updates section
        }
        
        // results
        if( res.result ) {
            var returns = [];
            res.result.forEach( function( ret ) {
                if( typeof ret === 'string' && ret.startsWith( 'v' ) ) {
                    returns.push( ret.substring(1) );
                } else {
                    returns.push( fetch( ret ) );
                }
            } );
            return (returns.length > 1 || expectAlist) ? returns : returns[0];
        }
    }; //processRaw

    yote.processRaw = processRaw;

    yote._raw_steps = [];
    yote.addRawStep = function( step ) {
        yote._raw_steps.push( step );
    }
    yote.clearRawSteps = function() { yote._raw_steps = []; }
    yote.getRawSteps = function() { return yote._raw_steps; }

    // yote objects can be stored here, and interpreting
    // etc can be done here, the get & stuff
    var returnVal = '';
    var reqListener = function( returnRaw, handl ) { 
        return function() {
            console.log( "GOT [ " + workerTxt + "] FROM SERVER : " + this.responseText );
            if( isWorker ) {
                yote.addRawStep( this.responseText );
            }
            if( isWorker &&  !returnRaw ) {
                returnVal = processRaw( this.responseText );
            } else {
                returnVal = this.responseText; 
            };
            if( handl ) {
                handl( returnVal );
            }
        };
    };

    function readyObjForContact( obj ) {
        if( typeof obj !== 'object' ) {
            return typeof obj === 'undefined' ? undefined : 'v' + obj;
        }
        if( id2obj[ obj.id ] === obj ) {
            return obj.id;
        }

        for( var idx in obj ) {
            var v = obj[idx];
            if( typeof v === 'object' ) {
                if( id2obj[ v.id ] === v ) {
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

    var contact = function(id,action,data,returnRaw,handl) { 
        var oReq = new XMLHttpRequest();
        oReq.addEventListener("load", reqListener( returnRaw,handl ) );

        console.log( "[ " + workerTxt + "] contacting server via url : " + ( yoteServerURL || "" ) + 
                     '/' + id +
                     '/' + ( yote.token ? yote.token : '_' ) + 
                     '/' + action )
        
        oReq.open("POST", ( yoteServerURL || "" ) + 
                  '/' + id +
                  '/' + ( yote.token ? yote.token : '_' ) + 
                  '/' + action, 
                  ! isWorker ); // ! isWorker is the same as async

        var readiedData = readyObjForContact( data );
        var sendData = JSON.stringify(  typeof readiedData === 'object' ? readiedData : [ readiedData ] );
        console.log( " [ " + workerTxt + "] About to send to server : " + sendData );
//        oReq.send( sendData ? 'p=' + sendData : undefined );
        // data must always be an array, though that array may have different data structures inside of it
        // as vehicles for data
        oReq.send( sendData || '' );

        return returnVal; //returnVal is set by the reqListener
    }; // contact

    
    yote.worker_init_root = function() {
        return contact('_', 'init_root' );
    }; //yote._raw_root

    var workers = {};

    // translates text to objects
    yote.xform_in = function( item ) {
        if( typeof item === 'object' ) {
            if( item === null ) {
                return undefined;
            }
            if( Array.isArray( item ) ) {
                return item.map( function( x ) { return yote.xform_in(x); } );
            } else {
                var ret = {};
                for( var k in item ) {
                    ret[ k ] = yote.xform_in( item[k] );
                }
                return ret;
            }
        } else {
            if( typeof item === 'undefined' ) return undefined;
            if( typeof item === 'string' && item.startsWith('v') ) {
                return item.substring( 1 );
            } else {
                return id2obj[ item ];
            }
        }
    }
    
    // contacts worker immediately
    yote.callWorker = function( args ) {
        var workerUrl   = "js/worker-yote.js",
            callParams  = args.params, 
            callback    = args.callback,
            callpath    = args.callpath,
            failhanlder = args.failhandler, 
            calltype    = args.callType || 'function_call',
            expectAlist = args.expectReturnedList;
        // have to find a way to get the update arguments from the
        // controls
        var worker = workers[ workerUrl ];
        if( ! worker ) {
            worker = new Worker( "/__/" + workerUrl );
            workers[ workerUrl ] = worker;
        }
        worker.onmessage = function( e ) { 
            // possibility for foolishly changing the handlers?
            // at processing the raw, this process will have access 
            // to all the yote data'
            console.log( "GOT [ " + workerTxt + "] FROM WORKER : " + e.data );
            var resp = JSON.parse( e.data );
            var ok   = resp[0];
            if( ok === 'OK' ) {
                var rawRespData = resp[2];

                for( var i=0; i<rawRespData.length; i++ ) {
                    yote.processRaw( rawRespData[i] );
                }
                var resp = yote.xform_in( resp[1] );

                if( callback ) {
                    callback( resp );
                }
            }
        }
        worker.postMessage( [ calltype, yote.xform_out( callParams ), callpath ] );
    }; //yote.callWorker

    // transform from objects to text
    yote.xform_out =  function( res ) {
        if( typeof res === 'object' ) {
            if( Array.isArray( res ) ) {
                return res.map( function( x ) { return yote.xform_out( x ) } );
            }
            var obj = yote.__object_library[ res.id ];
            if( obj ) { return res.id }
            var ret = {};
            for( var key in res ) {
                ret[key] = yote.xform_out( res[key] );
            }
            return ret;
            
        }
        if( typeof res === 'undefined' ) return undefined;
        return 'v' + res;
    }//yote.xform_out


    yote.doSequence = function( functions ) {
        if( typeof functions !== 'object' || functions.length === 0 ) {
            console.error( " [ " + workerTxt + "] Error, yote.doSequence called without worker" );
            return this;
        }
        return {
            functions    : functions,
            done_fun     : [],
            step         : 0,
            failHandlers : {},
            fail : function( step, failfun ) {
                this.failHandlers[ step ] = failfun;
                return this;
            },
            reset : function() {
                this.functions = this.done_fun.concat( this.functions );
                this.step = 0;
                return this;
            },
            start : function() {
                var that = this;
                if( this.functions.length > 0 ) {
                    var fun = this.functions.shift();
                    this.done_fun.push( fun );
                    console.log( [" [ " + workerTxt + '] start  got fun', fun ] );
                    fun( function() { that.start(); that.step++ },
                     function( err ) {
                         if( yote.failHandlers["++*"] ) {
                             yote.failHandlers["++*"](err);
                         }
                         if( yote.failHandlers[this.step] ) {
                             yote.failHandlers[this.step](er);
                         }
                         if( yote.failHandlers["*++"] ) {
                             yote.failHandlers["*++"](err);
                         }
                     } );
                } //if functions
                return this;
            }
        };
    }; //yote.doSequence


    yote.apps = {};
    yote.fetch_app = function( appname ) {
        var app = yote.apps[ appname ];
        if( app ) {
            return app;
        }
        
        if( isWorker ) { //safe to directly call
            app = yote.root.fetch_app( appname );
            if( app ) {                
                yote.apps[ appname ] = app;
                return app;
            } else {
                console.warn( " [ " + workerTxt + "] Unable to fetch app '" + appname + "'" );
            }
        }
        else {
            console.warn( " [ " + workerTxt + "] NON WORKER FETCHING CALL" );
        }
    }; //fetch_app

    yote.loadApp = function( appname, callback ) {
        return function( cb, failhandler ) {
            yote.callWorker( {
                params    : [ appname ],
                callType  : 'fetch_app',
                callback  : function( result ) {
                    yote.apps[ appname ] = result;
                    if( callback ) callback( result );
                    cb();
                },
                failhandler : failhandler
            } );
        };
    };

    yote.initRoot = function( appname, callback ) {
        return function( cb, failhandler ) {
            yote.callWorker( {
                params    : [],
                callType  : 'init_root',
                callback  : function( result ) {
                    yote.root  = result[0];
                    yote.token = result[1]
                    
                    if( callback ) callback( result );
                    cb();
                },
                failhandler : failhandler
            } );
        };
    };

    yote.workerLoadInclude = function( includeFile ) { // TODO : make this a list of 'em
        return function( callback, failhandler ) {
            yote.callWorker( {
                params    : [ includeFile ],
                callType  : 'include',
                callback  : callback,
                failhandler : failhandler
            } );
        };
    }; //yote.workerLoadInclude
    yote.readyWorkerCall = function( callname, args ) {
        return function( callback, failhandler ) {
            yote.callWorker( {
                callType  : 'function_call',
                callpath    : callname,
                params      : args || [],
                callback    : callback,
                failhandler : failhandler
            } );
        };
    }; //yote.readyWorkerCall

}; //yote._init
