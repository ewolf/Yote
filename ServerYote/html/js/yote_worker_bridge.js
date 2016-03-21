yote = {};
yote_worker_bridge = yote;
yote_worker_bridge.init = function( initFun ) {
    var myWorker = new SharedWorker("/__/js/yote_worker.js");

    var _callRegistry = {};

    var _stamp_methods = {};

    var _id2obj = {};

    //
    //  One handler to handle them all. That is why all calls have
    //  the exact same protocol.
    //
    myWorker.port.onmessage = function(e) {
        alert( e.data );
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
                    _listeners : {},
                    addUpdateListener : function( fun, tag ) {
                        tag = tag || '_';
                        this._listeners[ tag ] = fun;
                    },
                    fireAllUpdateListeners : function() {
                        var tag;
                        for( tag in this._listeners ) {
                            this._listeners[tag]( this, arguments );
                        }
                    },
                    fireUpdateListener : function( tag, msg ) {
                        var listener = this._listeners[ tag ];
                        if( listener ) {
                            listener( this, msg );
                        } else {
                            console.warn( "No listeners for '" + tag + "'" );
                        }
                    },
                    get : function( key ) {
                        var val = this._d[key];
                        if( typeof val === 'string' && val.startsWith( 'v' ) )
                            return val.substring(1);
                        var obj = _id2obj[ val ];
                        if( ! obj ) {
                            console.warn( "Requested item of id '" + val + "' but it was not present" );
                        }
                        return obj;
                    },
                    add_to : _makeMethod( 'add_to' ),
                    remove_from : _makeMethod( 'remove_from' ),
                    set : _makeMethod( 'set' ),
                    update : _makeMethod( 'update' )
                }; //new obj
                // set up RPC methods. The methods are defined by the stamps
                for( var j=0,jlen=stamps.length; j<jlen; j++ ) {
                    var methods = _stamp_methods[ stamps[j] ];
                    if( methods ) {
                        for( var k=0,klen=methods.length; k<klen; k++ ) {
                            obj[ methods[k] ] = _makeMethod( methods[k] );
                        }
                    } else {
                        console.warn( "Warning : no methods found for stamp '" + stamps[j] + "'" );
                    }
                } //each stamp
            } //if new obj
            obj._d = data;
        } //updates

        function _makeMethod( name ) {
            return function( args, fun ) {
                _contact( [ this.id, name, args ], fun );
            }
        }

        // finally activate the callback.
        var method = _callRegistry[key];
        if( method ) {
            delete _callRegistry[key];
            method( result );
        }
    }; //myWorker.port.onmessage

    function _contact( args, fun ) {
        console.log( "GOT CONTACT REQ");

        var key = new Date().getTime();
        
        while( _callRegistry[key] ) { key = key + "X"; }
        _callRegistry[key] = fun;
        myWorker.port.postMessage( [ key, args ] );
        console.log( "POSTED MESG");
    }

    myWorker.port.start();

    // root object always has id 1 and has the init method, which sends
    // back the root object
    _contact( [ 1, 'init' ], function( root ) {
                console.log( "GOT CONTACT RESP");
        if( initFun ) {
            initFun( root );
        } else {
            console.warn( "No init fun given" );
        }
    } );

}; //yote_worker_bridge.init

yote_worker_bridge.init();

console.log( "yote_worker_bridge load" );


