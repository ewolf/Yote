var assert = require( 'assert' );

var yote = require( './Yote.js' );
var root = yote.getRoot();

assert( root, "Has root" );

root.F = 'B';

assert.equal( root.F, "B" );

root.O = {};
var o = root.O;
o.ORF = "FOO";

assert.equal( root.O.ORF, "FOO" );

console.log( '--------------');
o.ARR = [ 4, 5, 6 ];
console.log( '--------------');
console.log( ['one',root] );
console.log( ['two',root.O] );
console.log( ['two',root.O.ARR] );
//filter filters out the _y hash attached to the array 
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
