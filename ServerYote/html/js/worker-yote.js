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

    var type = data[0];
    if( type === 'include' ) {
        for( var i=1, len=data.length; i<len; i++ ) {
            importScripts( data[i] );
        }
        return resp( 'IMPORTED' );
    }
    else if( type === 'call' ) {
        var obj = root.fetch_app( data[1] );
        if( ! obj ) {
            return err( "Could not find app");
        }
        var objPath = data[2].split(".");
        for( var i=0, len = objPath.length; i<len; i++ ) {
            obj = obj.get( objPath[i] );
            if( ! obj ) {
                return err( "Could not find app");
            }
        }
        var method = obj[ data[3] ];
        if( ! method ) {
            return err( "method not found" );
        }
        var rawResp = method( data[4], true );
        return resp( rawResp );
    }
} //onMessage
