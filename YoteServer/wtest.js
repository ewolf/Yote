importScripts( 'yote.js' );
onmessage = function(e) {
    console.log( "Worker got messsage", e );
    postMessage( contact() );
}
