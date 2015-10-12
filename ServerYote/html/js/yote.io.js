var worker = new Worker( "/__/js/yote.main.js" );
window.yotecall = function( funcall, args, oncall ) {
    var yargs = args.map( function( val ) {
        if( typeof val === 'object' ) {
            
        } else {
            return 'v' + val;
        }
    } );
    worker.postMessage( yargs );
    worker.onmessage = function( e ) {
        var data = e.data; //json-y blob?
        var data_transformed;
        funcall( data_transformed );
    }


    var ret = window[ funcall ](  );
    
} //window.yotecall

