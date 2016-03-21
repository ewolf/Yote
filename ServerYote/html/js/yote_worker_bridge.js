/*jslint white: true */
/*jslint nomen: true */
/*jslint plusplus : true */

// the exception is so that things can easily be wrapped inside a onReady sort of thing
yote_worker_bridge = { init : function() { throw new Error("yote_worker_bridge not yet loaded"); } };
yote_worker_bridge.init = function( initFun ) {


    //  foo.barmethod = function( args, fun ) {
    //    register key --> fun
    //     myworker.port.postmessage( [ key, args ] );
    //  }

    //  onmessage = function(e) {
    //    key = e.data[0]
    //    result = e.data[1]
    //    updates = e.data[2]
    //    find fun registered to key
    //    remove registration
    //    activate fun
    //  }
    
    var myWorker = new SharedWorker("yote_worker.js");

    var _callRegistry = {};

    var _stamp_methods = {};

    var _id2obj = {};

    /*
      One handler to handle them all. That is why all calls have
      the exact same protocol.
     */
    myWorker.port.onmessage = function(e) {
        var key     = e.data[0];
        var result  = e.data[1];
        var updates = e.data[2]; // [] 
        var methods = e.data[3]; // {}

        // update any info on stamps
        for( var stamp in methods ) {
            // used to attach methods to objects
            _stamp_methods[ stamp ] = methods[stamp];
        }

        // get any object updates. init sends back all known
        // objects, but if any new are created or updated
        // since all the objects were sent, this refreshes everything
        for( i=0,len=updates.length; i<len; i++ ) {
            // objects that have been updated
            var upd = updates[i];
            var id     = upd[0];
            var stamps = upd[1];
            var data   = upd[2];

            var obj = _id2obj[ id ];
            if( ! obj ) {
                obj = {
                    id  : id,
                    get : function( key ) {
                        var val = this._d[key];
                        if( typeof val === 'string' && val.startsWith( 'v' ) )
                            return val.substring(1);
                        var obj = _id2obj[ val ];
                        if( ! obj ) {
                            console.warn( "Requested item of id '" + val + "' but it was not present" );
                        }
                        return obj;
                    }
                };
                // set up RPC methods. The methods are defined by the stamps
                for( var j=0,jlen=stamps.length; j<jlen; j++ ) {
                    var methods = _stamp_methods[ stamps[j] ];
                    if( methods ) {
                        for( var k=0,klen=methods.length; k<klen; k++ ) {
                            obj[ methods[k] ] = function( args, fun ) {
                                _contact( [ this.id, methods[k], args ], fun );
                            }
                        }
                    } else {
                        console.warn( "Warning : no methods found for stamp '" + stamps[j] + "'" );
                    }
                }
            }
        } //updates

        // finally activate the callback.
        var method = _callRegistry[key];
        if( method ) {
            delete _callRegistry[key];
            method( result );
        }
    };

    function _contact( args, fun ) {
        var key = new Date().getTime();
        
        //goofy logic to make this atomic. Would be rare for this to trip and even rarer more than once.
        //maybe once computers get an order of magnitude faster
        while( _callRegistry[key] ) { ( key = key + "X" ) && (( ! _callRegistry[key] ) || _callRegistry[key] = fun ); }
        
        myWorker.port.postMessage( [ key, args ] );
    }

    myWorker.port.start();

    // root object always has id 1 and has the init method, which sends
    // back the root object
    contact( [ 1, 'init' ], function( root ) {
        if( initFun ) {
            initFun( root );
        } else {
            console.warn( "No init fun given" );
        }
    } );

}; //yote.init

/*
THINK ABOUT HOW THIS WILL BE USED.
   yote_worker_bridge.init( function( root ) {
      root.get("name");
      root.get("nos").isHidden( id ) ?
   } );

*/
