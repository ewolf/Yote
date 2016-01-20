importScripts( '/__/js/yote.js' );

yote.initWorker();


// transform the response into something anyone can use
function xform_out( res ) {
    if( typeof res === 'object' ) {
        if( Array.isArray( res ) ) {
            return res.map( function( x ) { return xform_out( x ) } );
        }
        var obj = yote.__object_library[ res.id ];
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

function resp( res ) {
    console.log( "WORKER SENDING BACK : "  + JSON.stringify( [ 'OK', xform_out( res ), yote.getRawSteps() ] ) );
    postMessage( JSON.stringify( [ 'OK', xform_out( res ), yote.getRawSteps() ] ) );
    yote.clearRawSteps();
}
function err( msg ) {
    console.log( "WORKER SENDING BACK : "  + JSON.stringify( [ 'ERR', msg ] ) );
    postMessage( JSON.stringify( [ 'ERR', msg ] ) );
    yote.clearRawSteps();
}

onmessage = function(e) {
    var data = e.data; 
    // _import, file1, file2, file3....
    // _call, app, object, method, args
    console.log( "WORKER GOT : "  + JSON.stringify( data ) );

    if( data.length < 2 || data.length > 3 ) {
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
        var rawResp =  yote.fetch_app( params[0] );
        return resp( rawResp );
    }
    else if( type === 'init_root' ) {
        var res = yote.worker_init_root();
        yote.root = res[0];
        yote.token = res[1];
        return resp( res );
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
} //onMessage
