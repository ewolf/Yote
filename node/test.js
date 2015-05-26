var fs = require('fs');
var a = require('assert');

var stores = require( './FixedStore' );

var path = '/tmp/foo';
function sz(msg) {
    if( ! msg ) msg = '';
    var sz = fs.statSync(path).size;
    console.log(msg + ")" + sz );
    return sz;
}

function testA() {
    sz();
    stores.open( path, 50, function( err, store ) {
        sz('zero id');
        a.equal( store.nextIdSync(), 1, "first id" );
        sz('first id');
        a.equal( store.nextIdSync(), 2, "second id" );
        sz('second id');
        a.equal( store.nextIdSync(), 3, "third id" );
        sz('third id');

        store.putRecordSync( 1, new Buffer("FOO") );
        store.putRecordSync( 3, new Buffer("BAR") );
        store.putRecordSync( 2, new Buffer("BONGLO") );
        store.putRecordSync( 1, new Buffer("OFO") );

        console.log( '---done testA---' );
        testB();
    } );
}

function testB() {
    sz();
    stores.open( path, 50, function( err, store ) {
        sz('after 3rd id');
        a.equal( store.nextIdSync(), 4, "4th id" );
        sz('first id');
        a.equal( store.nextIdSync(), 5, "5th id" );
        a.equal( sz('second id'), 5*50 );
        a.equal( store.nextIdSync(), 6, "6th id" );
        a.equal( sz('second id'), 6*50 );

        store.putRecordSync( 1, new Buffer("FOO") );
        store.putRecordSync( 3, new Buffer("BAR") );
        store.putRecordSync( 2, new Buffer("BONGLO") );
        store.putRecordSync( 1, new Buffer("OFO") );

        [1,2,3,4,5,6].forEach(function(x){ console.log( x + ') ' + store.getRecordSync(x) ); });
        
        console.log( '---done testB---' );
        fs.unlinkSync( path );
    } );
}

testA();
