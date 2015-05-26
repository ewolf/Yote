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


