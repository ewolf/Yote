/* 
   library file for calc test


   note : this relies upon the worker-yote and the non-worker runtime
    to call for yote initialization, therefore: 
        NO YOTE INITIALIZATION BELONGS IN THIS FILE
*/
var app, currScenario;

var reset = yote.registerFunction( 'reset', function() {
    app.reset();
    var scenarios = app.get( 'scenarios' );
    yote.expose( app, scenarios, scenarios.toArray() );

} );

function expose_all() {
    var scenarios = app.get( 'scenarios' ).toArray();
    for( var i=0; i<scenarios.length; i++ ) {
        var lines = scenarios[i].get( 'product_lines' ).toArray();
        for( var j=0; j<lines.length; j++ ) {
            var line = lines[j];
            var steps = line.get('steps').toArray();
            yote.expose( line, steps );
            for( var k=0; k<steps.length; k++ ) {
                yote.expose( steps[k] );
            }
        }
    }
    
}

var addEntry = yote.registerFunction( 'addEntry', function(args) {
    var parent = args[0], listname = args[ 1 ];
    var newentry = parent.add_entry( [ listname ] );
    expose_all();
    return newentry;
    
} );

var init = yote.registerFunction( 'init', function() {
    app = yote.fetch_app( 'CalcTest' );
    expose_all();
    currScenario = app.get( 'current_scenario' );
    return currScenario;
} );

var select_scenario = yote.registerFunction( 'select_scenario', function( scenario ) {
    var lines = scenario.get( 'product_lines' );
    yote.expose( lines.toArray() );
    app.setCurrentScene( scenario );
    currScenario = scenario;
console.warn( ['zoinks', currScenario.get( 'product_lines' ).toArray() ] );
    yote.expose( currScenario.get( 'product_lines' ).toArray() );
    
    return scenario;
} );

var reset = yote.registerFunction( 'reset', function() {
    app.reset();
    init();
} );
