var fs = require('fs');
var a = require('assert');

console.log( '--------------- test store --------------' );

var stores = require( './FixedStore' );

var path = '/tmp/foo';
try { fs.unlinkSync( path ); } catch(e){}

function testA() {
    stores.open( path, 50, function( err, store ) {
        a.equal( store.nextIdSync(), 1, "first id" );
        a.equal( store.nextIdSync(), 2, "second id" );
        a.equal( store.nextIdSync(), 3, "third id" );

        store.putRecordSync( 1, new Buffer("FOO") );
        store.putRecordSync( 3, new Buffer("BAR") );
        store.putRecordSync( 2, new Buffer("BONGLO") );
        store.putRecordSync( 1, new Buffer("OFO") );

        console.log( '---done testA---' );
        testB();
    } );
}

function testB() {
    stores.open( path, 50, function( err, store ) {
        a.equal( store.nextIdSync(), 4, "4th id" );
        a.equal( store.nextIdSync(), 5, "5th id" );
        a.equal( store.nextIdSync(), 6, "6th id" );

        store.putRecordSync( 1, new Buffer("FOO") );
        store.putRecordSync( 3, new Buffer("BAR") );
        store.putRecordSync( 2, new Buffer("BONGLO") );
        store.putRecordSync( 1, new Buffer("OFO") );

        [ [1,"OFO"],[2,"BONGLO"],[3,"BAR"],[4,""] ]
            .forEach(function(x){ a.equal( store.getRecordSync(x[0]).toString(), x[1] ); });
        
        console.log( '---done testB---' );
    } );
}

testA();

//fs.unlinkSync( path );

console.log( '--------------- test recycle store --------------' );

