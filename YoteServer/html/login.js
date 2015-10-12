importScripts( '/__/js/yote.js' );
yote.init();

var root = yote.fetch_root();
var app  = yote.fetch_app( 'myapp' );
onmessage = function(e) {
    var data = e.data;
    var name = data[0], pw = data[1];
    var res = app.login( name, pw );
    var resTranslated = res;
    postMessage( resTranslated );
}
