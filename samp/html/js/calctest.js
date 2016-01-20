/* 
   library file for calc test


   note : this relies upon the worker-yote and the non-worker runtime
    to call for yote initialization, therefore: 
        NO YOTE INITIALIZATION BELONGS IN THIS FILE
*/


yote.registerFunction( 'calc', function( params ) {
    var app = yote.fetch_app( 'CalcTest' );
    return app.calc( [params.number_employees, params.hourly_wage], true );
} );

yote.registerFunction( 'init', function() {

} );

yote.registerFunction( 'reset', function() {
    var app = yote.fetch_app( 'CalcTest' );
    app.reset();

} );


yote.registerFunction( 'new_scene', function() {
    var app = yote.fetch_app( 'CalcTest' );
    return app.new_scene([], true);
} );
