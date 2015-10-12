importScripts( 'yote.js' );
var root = yote.fetch_root(); // <--- got to here, but init is not fully complete
console.log( [ root, root.data, root.cls, root.test, 'GOTTY ROO' ] );
console.log( root.test( [ "WOO", 'AH' ] ) );

onmessage = function(e) {
    console.log( "Worker got messsage from main page", e );
    
}
