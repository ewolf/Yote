var yote = {
    fetch_root : function() {
        throw new Error("init must be called before fetch_root");
    }
}; // yote var

yote.initMain = function( yoteServerURL ) {
    yote._init( yoteServerURL );
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
        return function( data, args, rawOrHandler ) {
            if( typeof rawOrHandler === 'boolean') {
                var useRaw = rawOrHandler;
            } else {
                var sucHandler = rawOrHandler;
            }

            if( ! isWorker && sucHandler ) {
                console.warn( "yote warning. method '" + nm + "' called without a success handler" );
                // big warnings anyway, using this as not a worker
                // since if there is a worker, its object cache may become out of date :/
                // TODO: yote worker methods rather than onmessage? 
                // maybe even grab window.onmessage
            }
            var id = this.id;
            var res = contact( id, nm, data, args, useRaw );
            if( isWorker ) { 
                return res; 
            }
            if( sucHandler ) {
                sucHandler();
            }
        };
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
        obj.data = datastructure.data;
        obj.get = function( key ) {
            var val = this.data[key];
            if( val.startsWith( 'v' ) ) {
                return val.substring( 1 );
            } 
            return fetch( val );
        };
        obj.toData = function() {
            return { id  : this.id,
                     cls : this.cls,
                     data : this.data
                   };
        }; //ugh, case of a list returned?
        
        var mnames = class2meths[ datastructure.cls ] || [];
        mnames.forEach( function( mname ) {
            obj[ mname ] = makeMethod( mname );
        } );
    } //makeObj
    
    var processRaw = function(rawResponse) {
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
        return returns.length > 1 ? returns : returns[0];
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

    var contact = function(id,action,data,returnRaw) { // args has async,sucHandler,failHandler,returnRaw
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
        token = contact('_', 'create_token');
        this.root = contact('_', 'fetch_root');
        return this.root;
    }; //yote.fetch_root

    var workers = {};

    yote.call = function( workerUrl, args, callback ) {
        var worker = workers[ workerUrl ];
        if( ! worker ) {
            worker = new Worker( "/__/" + workerUrl );
            workers[ workerUrl ] = worker;
        }
        worker.onmessage = function( e ) { //possibility for foolishly changing the handlers?
            // at processing the raw, this process will have access to all the yote data'
            var resp = yote.processRaw( e.data );
            if( callback ) {
                callback( resp );
            }
        }
        worker.postMessage( args );
    }; //yote.call


}; //yote._init
