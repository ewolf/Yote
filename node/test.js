var assert = require( 'assert' );

var yote = require( './index.js' );
var root = yote.getRoot();

assert( root, "Has root" );

root.set("F","B");

assert.equal( root.get("F"), "B" );

var o = yote.newObj();
root.set( "O", o );

o.set("ORF","FOO");

assert.equal( root.get("O").get("ORF"),"FOO" );

o.set("ARR", [ 4, 5, 6 ] );

//filter filters out the _y hash attached to the array 
assert.deepEqual( root.get("O").get("ARR").filter( function(item) { return true; } ), [ 4, 5, 6 ] );

var oo = yote.newObj();
oo.set("DOODOO", "WHODO" );

o.set("HAA", { 'objy' : oo, 'backref' : o } );

var hash = root.get("O").get("HAA");
var y = delete hash._y; //remove this for the comparison

assert.deepEqual( hash, { 'objy' : oo, 'backref' : o } );

hash._y = y; //add this back so things work as normal

assert.deepEqual( hash, root.get("O").get("HAA") );

var arr = root.get("O").get("ARR");
arr.push( hash );

assert.deepEqual( arr.filter( function(item) { return true; } ), [ 4, 5, 6, hash ] );
