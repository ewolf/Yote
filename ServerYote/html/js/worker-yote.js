importScripts( '/__/js/yote.js' );

yote.initWorker();

console.log( "worker-yote.js init" );

var root = yote.fetch_root();

function resp( msg ) {
    postMessage( JSON.stringify( [ 'OK', msg ] ) );
}
function err( msg ) {
    postMessage( JSON.stringify( [ 'ERR', msg ] ) );
}

onmessage = function(e) {
    var data = e.data; 
    // _import, file1, file2, file3....
    // _call, app, object, method, args
    console.log( [ "worker-yote.js GOT MESSAGE", data ] );

    if( data.length != 2 ) {
        console.warn( "worker given something other than two parameters : " + data.join(",") );
    }

    var type   = data[0];
    var params = data[1];

    if( type === 'include' ) {
        for( var i=0, len=params.length; i<len; i++ ) {
            console.log( "worker importing " + params[i] );
            importScripts( params[i] );
        }
        return resp();
    }
    else if( type === 'fetch_app' ) {
        var rawResp =  root.fetch_app( params[0], true );
        return resp( rawResp );
    }
    else if( type === 'call' ) {
        var funcpath = data[ 2 ].split( '.' );
        var funcall = yote.functions;
        for( var i=0, len=funcpath.length; i < len; i++ ) {
            funcall = funcall[ funcpath[i] ];
            if( ! funcall ) {
                return err( "path not found" );
            }
        }
        return resp( funcall(params) );
    }
    else if( type === 'sync-with-worker' ) {
        // sync up the main thread objects with those in the
        // worker thread. This does not require a call to 
        // the server. This rather than the fetch app and everything?
        return resp( JSON.stringify( yote.__object_library ) );
    }
} //onMessage
