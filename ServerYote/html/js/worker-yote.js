importScripts( '/__/js/yote.js' );

yote.initWorker();


function resp( res ) {
    console.log( "WORKER SENDING BACK : "  + JSON.stringify( [ 'OK', yote.xform_out( res ), yote.getRawSteps() ] ) );
    postMessage( JSON.stringify( [ 'OK', yote.xform_out( res ), yote.getRawSteps() ] ) );
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
    var params = yote.xform_in( data[1]);

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
    else if( type === 'function_call' ) {
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

    else if( type === 'method_call' ) {
        // params is a list of the form [ object, methodname, params ]
        var ret = params[0][ params[1] ]( params[2] );
        return resp( ret );
    }

} //onMessage
