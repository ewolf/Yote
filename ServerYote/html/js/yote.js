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
        for( var cls in res.methods ) {
            class2meths[cls] = res.methods[ cls ];
        }
        
        // updates
        res.updates.forEach( function( upd ) {
            makeObj( upd );
        } ); //updates section
        
        // results
        var returns = [];
        res.result.forEach( function( ret ) {
            if( ret.startsWith( 'v' ) ) {
                returns.push( ret.substring(1) );
            } else {
                returns.push( fetch( ret ) );
            }
        } );
        return (returns.length > 1 || expectAlist) ? returns : returns[0];
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
        if( data && typeof data !== 'object' ) {
            data = [ data ];
        }
        oReq.send(data ? 'p=' + data.map(function(p) {
            return typeof p === 'object' ? p.id : 'v' + p }).join('&p=') 
                  : undefined );
        return returnVal;
    }; // contact
    
    yote.fetch_root = function() {
        //want a session object as well as a token
        token = contact('_', 'create_token');
        this.root = contact('_', 'fetch_root');
        return this.root;
    }; //yote.fetch_root

    var workers = {};

    yote.call = function( workerUrl, args, callback, expectReturnedList ) {
        return yote._call( {
            workerUrl   : args.workerUrl, 
            callArgs    : args.args, 
            callback    : args.callback, 
            failhanlder : args.failhandler, 
            expectAlist : args.expectReturnedList
        } );
    }
    yote._call = function( args ) {
        var workerUrl = args.workerUrl, 
            callArgs = args.args, 
            callback = args.callback, 
            failhanlder = args.failhandler, 
            expectAlist = args.expectReturnedList;
        // have to find a way to get the update arguments from the
        // controls
        var worker = workers[ workerUrl ];
        if( ! worker ) {
            worker = new Worker( "/__/" + workerUrl );
            workers[ workerUrl ] = worker;
        }
        worker.onmessage = function( e ) { //possibility for foolishly changing the handlers?
            // at processing the raw, this process will have access to all the yote data'
            var resp = yote.processRaw( e.data, expectAlist );
            if( callback ) {
                callback( resp );
            }
        }
        worker.postMessage( args );
    }; //yote.call

    var _inputsForAction, _displaysForAction, _actions = [];

    yote._findControls = function() {
        _inputsForAction   = {};
        _displaysForAction = {};

        var inputs   = document.getElementsByClassName( 'yote-input' );
        for( var i=0, len = inputs.length; i<len; i++ ) {
            var el = inputs[ i ];
            var actionName = el.getAttribute( 'data-yote-action' );
            if( actionName ) {
                var ifa = _inputsForAction[ actionName ];
                if( ! ifa ) {
                    ifa = [];
                    _inputsForAction[ actionName ] = ifa;
                }
                var paramnumber = parseInt( el.getAttribute( 'data-yote-param-number' ) );
                if( isNaN( paramnumber ) ) {
                    console.warn( "warning, parameter for " + actionname + " has no param number. ignoring" );
                } else {
                    ifa[ paramnumber ] = el;
                }
            }
        }

        var displays = document.getElementsByClassName( 'yote-display' );
        for( var i=0, len = displays.length; i<len; i++ ) {
            var el = inputs[ i ];
            var actionName = el.getAttribute( 'data-yote-action' );
            if( actionName ) {
                var ifa = _displaysForAction[ actionName ];
                if( ! ifa ) {
                    ifa = [];
                    _displaysForAction[ actionName ] = ifa;
                }
                ifa.push( el );
            }
        }

        var acts = document.getElementsByClassName( 'yote-action' );
        for( var i=0, len = acts.length; i<len; i++ ) {
            var el = acts[i];
            if( ! el.getAttribute( 'data-yote-acted' ) ) {
                el.setAttribute( 'data-yote-acted', 1 );
                _actions.push( el );
                el.addEventListener('click', yote._activateControl( el ) );
            }
        }
    }; //yote._findControls

    yote._activateControl = function(el) {
        return function() {
            var act     = el.getAttribute( 'yote-action' );
            var parmFun = el.getAttribute( 'yote-params' );
            if( ! act || ! parmFun ) {
                console.warn( "could not activate control. yote-action or yote-params not found" );
            }
            yote._call( "js/worker-yote.js", window[parmFun](), window[act] );
        };
    };

    yote.workerLoadInclude = function( includeFile, callback, failhandler ) {
        yote._call( {
            workerUrl : "js/worker-yote.js",
            callArgs  : [ 'include', [ includeFile ] ],
            callback  : callback,
            failhandler : failhandler
        } );
    };
    yote.newCall = function( callFunctionName ) {
        // look at registered contols and send the variables over
//        yote.call( "js/worker-yote.js", window[](), window[act] );
        yote._call( "js/worker-yote.js", 'call', window[](), window[act] );
    };

}; //yote._init
