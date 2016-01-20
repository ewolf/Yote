/* 
   library file for calc test


   note : this relies upon the worker-yote and the non-worker runtime
    to call for yote initialization, therefore: 
        NO YOTE INITIALIZATION BELONGS IN THIS FILE
*/


var calc = yote.registerFunction( 'calc', function( params ) {
    var app = yote.fetch_app( 'CalcTest' );
    return app.calc( [params.number_employees, params.hourly_wage] );
} );

var init = yote.registerFunction( 'init', function() {
    var app = yote.fetch_app( 'CalcTest' );
    var scenes = app.get( 'scenarios' );
    yote.expose( app, scenes, scenes.toArray() );
} );

var select_scene = yote.registerFunction( 'select_scene', function( scene ) {
    var lines = scene.get( 'product_lines' );
    yote.expose( lines.toArray() );
} );

var reset = yote.registerFunction( 'reset', function() {
    var app = yote.fetch_app( 'CalcTest' );
    app.reset();
    init();
} );


var new_scene = yote.registerFunction( 'new_scene', function() {
    var app = yote.fetch_app( 'CalcTest' );
    return app.new_scene([]);
} );

var new_prod = yote.registerFunction( 'new_product_line', function() {
    var scene = yote.fetch_app( 'CalcTest' ).get_current_scene();
    return scene.new_productLine([]);
} );
