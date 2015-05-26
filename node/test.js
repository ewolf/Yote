var assert = require( 'assert' );

var yote = require( './index.js' );
var root = yote.getRoot();

assert( root, "Has root" );

r.set("F","B");
assert.equal( root.get("F"), "B" );

var o = yote.newObj();
r.set( "O", o );
o.set("ORF","FOO");

assert.equal( r.get("O").get("ORF"),"FOO" );


