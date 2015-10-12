importScripts( '/__/js/yote.js' );
yote.init();

var root = yote.fetch_root();
var app  = yote.fetch_app( 'Yote::App' );
onmessage = function(e) {
    var data = e.data;
    var name = data[0], pw = data[1];
    var rawResp = app.login( [ name, pw ], { rawResponse : true } );
    postMessage( rawResp );
} //onMessage
