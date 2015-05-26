var test = require('tape');
var fs = require('fs');

var stores = require( './FixedStore' );

var path = '/tmp/foo';
try { fs.unlinkSync( path ); } catch(e){}

test( 'new record file', function(t) {
    t.plan(28);

    stores.open( path, 50, function( err, store ) {
        t.equal( store.nextIdSync(), 1, "first id" );
        sz( 50 );
        t.equal( store.nextIdSync(), 2, "second id" );
        sz( 100 );
        t.equal( store.nextIdSync(), 3, "third id" );
        sz( 150 );
        t.equal( store.nextIdSync(), 4, "fourth id" );
        sz( 200 );

        store.putRecordSync( 1, new Buffer("FOO") );
        store.putRecordSync( 3, new Buffer("BAR") );
        store.putRecordSync( 2, new Buffer("BONGLO") );
        store.putRecordSync( 1, new Buffer("OFO") );
        [ [1,"OFO"],[2,"BONGLO"],[3,"BAR"],[4,""] ]
            .forEach(function(x){ 
                t.equal( store.getRecordSync(x[0]).toString(), x[1] ); });
        testExistingRecordFile( );
    } ); //12 tests so far

    function sz(size,msg) {
        var sz = fs.statSync(path).size;
        t.equal( sz, size );
    }
    
    function testExistingRecordFile() {
        stores.open( path, 50, function( err, store ) {
            t.equal( store.nextIdSync(), 5, "5th id" );
            t.equal( store.nextIdSync(), 6, "6th id" );
            sz( 300 );
            store.putRecordSync( 4, new Buffer("onion") );
            store.putRecordSync( 6, new Buffer("pEte") );
            [ [1,"OFO"],[2,"BONGLO"],[3,"BAR"],[4,"onion"],[6,"pEte" ] ]
                .forEach(function(x){ 
                    t.equal( store.getRecordSync(x[0]).toString(), x[1] ); });
            fs.unlinkSync( path );
            t.comment( '---------- test async ------------' );
            testAsync();
        } ); //at 20 tests
    } //testExistingRecordFile

    var asyncStore;
    function getStore() { return asyncStore; }
    function testAsync() { 
        testAsyncGroups( [
            [
                "open store group",
                [ function() { stores },
                  function() { return stores.open },
                  function(err,store) {
                      asyncStore = store;
                  }, path, 50 
                ],
            ],
            [
                "first nextid group",
                [ getStore,
                  function() { return asyncStore.nextId },
                  function( err, id ) {
                      t.equal( id, 1, "first async nextid call" );
                      sz( 50 );
                  }
                ],
            ],
            [ "four more nextid group", 1,2,3,4 ].map( function(x) { return Number( x ) ?  [ getStore, function() { return asyncStore.nextId } ] : x; } ),
            [
                "sixth async group",
                [ getStore,
                  function() { return asyncStore.nextId },
                  function( err, id ) {
console.info( [ "SIXTH", this, err, id ] ); //called twice, so buug
console.trace();
                      t.equal( id, 6, "sixth async nextid call" );
                      sz( 300 );
                  }
                ],
            ],
            [ "Put Records Async", 2, 3, 5 ].map( function( n ) { 
                return Number(n) ?  [ getStore, function() { return asyncStore.putRecord }, function() {}, n, "Record " + n ] : n;
            } ),
            [ "Get Records Async", 2, 3, 5 ].map( function( n ) { 
                return Number(n) ?  [ getStore,function() { return asyncStore.getRecord }, function( err, buff ) {
                    t.equal( buff.toString(), "Record " + n, "Record " + n );
                }, n ] : n;
            } ),//28 tests
        ] );
    } //testAsync
        
    function testAsyncGroups( testgroups ) {
console.info( 'the start', testgroups );
        _testAsyncGroups( testgroups );
        
        function _testAsyncGroups( groups ) {
            var group = groups.shift();
            var title = group.shift();

            var countdown = group.length;
console.info( "start of group", title, countdown, group );

            console.log( '--- Starting : ' + title + ' ----');

            group.map( function( test ) {
                // group = [  [ test-function, callback, params... ] ]
                var self     = test.shift()();
                var testFun  = test.shift()();
                var callback = test.shift() || function() {};
                test.push( function() {
                    callback.apply( self, arguments );
console.trace("in group");
console.info( ["SUBTEST " + title +" DONE, countdown : " + countdown, arguments, callback+ '',  ] );
                    if( --countdown < 1 && groups.length > 0 ) {
                        console.log( '--- Done with : ' + title + ' ----');
                        _testAsyncGroups( groups );
                    }
                } );
                testFun.apply( self, test );
            } );
            console.log( '--- Queued : ' + title + ' ----');
        }
    } //testAsyncGroups
});

