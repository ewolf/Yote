var assert = require( 'assert' );
var fs = require( 'fs' );

console.log( '--- test fixed store---' );

var stores = require( './FixedStore.js' );

var tmpstore = '/tmp/foostore';
var store = stores.openSync( tmpstore, 50 );
assert.equal( store.nextIdSync(), 1, "first id" );
assert.equal( fs.statSync( '/tmp/foostore' ).size, 50, "first chunk written" );
assert.equal( store.nextIdSync(), 2, "second id" );
assert.equal( store.nextIdSync(), 3, "third id" );
assert.equal( fs.statSync( '/tmp/foostore' ).size, 150, "second and third chunks written" );
store.putRecord( 2, "DROOPY", function() {console.log( "BURROO" )} );

return;
console.log( [ "T", store.getRecordSync( 1 ).toString(), store.getRecordSync( 2 ).toString() ] );
assert.equal( store.getRecordSync( 2 ), "DROOPY", "wrote second record" );
assert.equal( fs.statSync( '/tmp/foostore' ).size, 100, "second chunk written didnt change size" );

fs.truncateSync( tmpstore );

console.log( '--- yote store---' );

var yote = require( './Yote.js' );
var root = yote.getRoot();

assert( root, "Has root" );

root.F = 'B';

assert.equal( root.F, "B" );

var o = root.O = yote.translate( {} );
o.ORF = "FOO";

assert.equal( root.O.ORF, "FOO" );

o.ARR = [ 4, 5, 6 ];

assert.deepEqual( root.O.ARR, [ 4, 5, 6 ] );


assert( root.O.ARR._y, "array is yote obj" );

var oo = {};
oo.DOODOO = "WHODO";

o.HAA = { 'objy' : oo, 'backref' : o };

var hash = root.O.HAA;

assert.deepEqual( hash, { 'objy' : oo, 'backref' : o } );
assert( hash._y, "hash is yote obj" );

assert.deepEqual( hash, root.O.HAA );

var arr = root.O.ARR;
arr.push( hash );

assert.deepEqual( arr, [ 4, 5, 6, hash ] );
assert( arr._y, "array is yote obj" );
