/* 
   library file for calc test


   note : this relies upon the worker-yote and the non-worker runtime
    to call for yote initialization, therefore: 
        NO YOTE INITIALIZATION BELONGS IN THIS FILE
*/
var app, currScene;

var calc = yote.registerFunction( 'calc', function( params ) {
    return app.calc( [params.number_employees, params.hourly_wage] );
} );

var init = yote.registerFunction( 'init', function() {
    app = yote.fetch_app( 'CalcTest' );
    var scenes = app.get( 'scenarios' );
    yote.expose( app, scenes, scenes.toArray() );
    currScene = app.get( 'current_scene' );
    if( currScene ) {
        yote.expose( currScene.get( 'product_lines' ).toArray() );
        return currScene;
    }
} );

var select_scene = yote.registerFunction( 'select_scene', function( scene ) {
    var lines = scene.get( 'product_lines' );
    yote.expose( lines.toArray() );
    app.setCurrentScene( scene );
    currScene = scene;
    yote.expose( currScene.get( 'product_lines' ).toArray() );
    
    return scene;
} );

var reset = yote.registerFunction( 'reset', function() {
    app.reset();
    init();
} );


var new_scene = yote.registerFunction( 'new_scene', function() {
    return app.new_scene([]);
} );

var new_prod = yote.registerFunction( 'new_product_line', function() {
    var scene = app.get('current_scene');
    var newprod = scene.new_product_line([]);
    return newprod;
} );
