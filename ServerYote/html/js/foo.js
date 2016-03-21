// for worker to load. Whee weee weee

var root = yote_worker.fetch_root();

yote_worker.addToStamps( 'some', function( obj ) {
    obj.howdy = function() { this.set("ooo","UUU"); return "HOWDY"; };
}, ['howdy'] );

var some = root.get( 'some', function() { return root.newobj( ['some']) } );
some.set("FOO", "baar" );


console.log( "FOOHERE" );
