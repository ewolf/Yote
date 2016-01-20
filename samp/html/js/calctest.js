/* 
   library file for calc test


   note : this relies upon the worker-yote and the non-worker runtime
    to call for yote initialization, therefore: 
        NO YOTE INITIALIZATION BELONGS IN THIS FILE
*/


yote.registerFunction( 'calc', function( params ) {
    console.log( "**** CALC CALLED ****" );
    console.log( [ 'PARAMS', params ] );
    var app = yote.fetch_app( 'CalcTest' );
    console.log( [ "APP IS ", app ] );
    app.calc( [params.number_employees, params.hourly_wage] );
} );

yote.registerFunction( 'init', function() {
    console.log( "**** CALC TEST INIT ****" );
} );
