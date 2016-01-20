var yote = {
    fetch_root : function() {
        throw new Error("init must be called before fetch_root");
    }
}; // yote var

yote.initMain = function( yoteServerURL ) {
    yote._init( yoteServerURL, false );
//    yote._findControls();
}; //initWorker

yote.initWorker = function( yoteServerURL ) {
    yote._init( yoteServerURL, true );
}; //initWorker

yote._init = function( yoteServerURL, isWorker ) {

    isWorker = isWorker ? true : false; // can't be undefined or things like that

    if( ! yoteServerURL ) { 
        yoteServerURL = '';
    }

    // cache storing objects and their meta-data
    var class2meths = {};
    var id2obj = {};

    // returns an object, either the cache or server
    var fetch = function( id ) {
        return id2obj[ id ] || this.root.fetch( id );
    }

    var token;
    
    // creates a proxy method that contacts the server and
    // returns data
    var makeMethod = function( mName ) {
        var nm = '' + mName;
        return function( data, rawOrHandler ) {
            if( typeof rawOrHandler === 'boolean') {
                var useRaw = rawOrHandler;
            } else {
                var sucHandler = rawOrHandler;
            }

            if( ! isWorker && sucHandler ) {
                console.warn( "yote warning. method '" + nm + "' called with a success handler but is not worker" );
                // big warnings anyway, using this as not a worker
                // since if there is a worker, its object cache may become out of date :/
                // TODO: yote worker methods rather than onmessage? 
                // maybe even grab window.onmessage
            }
            var id = this.id;
            var res = contact( id, nm, data, useRaw );
            if( isWorker ) { 
                return res; 
            }
            if( sucHandler ) {
                sucHandler();
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
        if( ! obj ) {
            obj = {};
            obj.id = datastructure.id;
            id2obj[ datastructure.id ] = obj;
        }
        obj._data = datastructure.data;
        obj.get = function( key ) {
            var val = this._data[key];
            if( val.startsWith( 'v' ) ) {
                return val.substring( 1 );
            } 
            return fetch( val );
        };
        obj._toData = function() {
            return { id  : this.id,
                     cls : this.cls,
                     data : this._data
                   };
        }; //ugh, case of a list returned?
        
        var mnames = class2meths[ datastructure.cls ] || [];
        mnames.forEach( function( mname ) {
            obj[ mname ] = makeMethod( mname );
        } );
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
                makeObj( upd );
            } ); //updates section
        }
        
        // results
        if( res.result ) {
            var returns = [];
            res.result.forEach( function( ret ) {
                if( ret.startsWith( 'v' ) ) {
                    returns.push( ret.substring(1) );
                } else {
                    returns.push( fetch( ret ) );
                }
            } );
            return (returns.length > 1 || expectAlist) ? returns : returns[0];
        }
    }; //processRaw

    yote.processRaw = processRaw;

    // yote objects can be stored here, and interpreting
    // etc can be done here, the get & stuff
    var returnVal = '';
    var reqListener = function( returnRaw ) { 
        return function() {
            if( isWorker && !returnRaw ) {
                returnVal = processRaw( this.responseText ); 
            } else {
                returnVal = this.responseText; 
            };
        };
    };

    function readyObjForContact( obj ) {
        if( typeof obj !== 'object' ) { return obj ? [obj] : undefined }
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
    }

    var contact = function(id,action,data,returnRaw) { 
        var oReq = new XMLHttpRequest();
        oReq.addEventListener("load", reqListener( returnRaw ) );

        console.log( '<<' + yoteServerURL + '>>' );
        console.log( 'url : ' + ( yoteServerURL || "" ) + 
                     '/' + id +
                     '/' + ( token ? token : '_' ) + 
                     '/' + action )
        
        oReq.open("POST", ( yoteServerURL || "" ) + 
                  '/' + id +
                  '/' + ( token ? token : '_' ) + 
                  '/' + action, 
                  ! isWorker );

        var sendData = JSON.stringify( readyObjForContact( data ) );
console.log( [ 'data', data ] );
console.log( "About to send " + sendData );
//        oReq.send( sendData ? 'p=' + sendData : undefined );
        // data must always be an array, though that array may have different data structures inside of it
        // as vehicles for data
        oReq.send( sendData || '' );

        return returnVal; //returnVal is set by the reqListener
    }; // contact
    
    yote.fetch_root = function() {
        //want a session object as well as a token
        token = contact('_', 'create_token');
        this.root = contact('_', 'fetch_root');
        return this.root;
    }; //yote.fetch_root

    var workers = {};

    // contacts worker immediately
    yote.callWorker = function( args ) {
        var workerUrl   = args.workerUrl, 
            callParams  = args.params, 
            callback    = args.callback, 
            failhanlder = args.failhandler, 
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
            var resp = yote.processRaw( e.data, expectAlist );
            if( callback ) {
                callback( resp );
            }
        }
        worker.postMessage( [ 'call', callParams ] );
    }; //yote.callWorker

    yote.doSequence = function( functions ) {
        if( typeof functions !== 'object' || functions.length === 0 ) {
            console.error( "Error, yote.doSequence called without worker" );
            return this;
        }
        return {
            functions    : functions,
            step         : 0,
            failHandlers : {},
            fail : function( step, failfun ) {
                this.failHandlers[ step ] = failfun;
                return this;
            },
            start : function() {
                var that = this;
                if( this.functions.length > 1 ) {
                    var fun = this.functions.shift();
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

    yote.loadApp = function( appname, callback ) {
        return function( cb, failhandler ) {
            yote.callWorker( {
                workerUrl : "js/worker-yote.js",
                params    : [ 'fetch_app', appname ],
                callback  : function( result ) {
                    callback( result );
                    cb();
                },
                failhandler : failhandler
            } );
        };
    };

    yote.workerLoadInclude = function( includeFile ) { // TODO : make this a list of 'em
        return function( callback, failhandler ) {
            yote.callWorker( {
                workerUrl : "js/worker-yote.js",
                params    : [ 'include', includeFile ],
                callback  : callback,
                failhandler : failhandler
            } );
        };
    }; //yote.workerLoadInclude
    yote.readyWorkerCall = function( callname, args ) {
        return function( callback, failhandler ) {
            yote.callWorker( {
                workerUrl   : "js/worker-yote.js",
                params      : [ 'call', args ], // automatically update objects? Maybe?? Not sure :/ will think
                callback    : callback,
                failhandler : failhandler
            } );
        };
    }; //yote.readyWorkerCall

}; //yote._init
