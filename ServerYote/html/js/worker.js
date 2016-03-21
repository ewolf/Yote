//web worker
onconnect = function(e) {
    console.log( "Worker got req" );

    var port = e.ports[0];

    port.addEventListener('message', function( e ) {
        var workerRes = "Got : " + e.data[0] + " " + e.data[1];
        port.postMessage([workerRes,2]);
    } );

    port.start();
}
