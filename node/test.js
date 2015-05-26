var test = require('tape');
var fs = require('fs');

var stores = require( './FixedStore' );

var path = '/tmp/foo';
try { fs.unlinkSync( path ); } catch(e){}

test( 'new record file', function(t) {
    t.plan(48);

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
        store.putRecordSync( 3, "BAR" );
        store.putRecordSync( 2, new Buffer("BONGLO") );
        store.putRecordSync( 1, new Buffer("OFO") );
        t.equal( store.pushSync( new Buffer("PUSHED") ), 5, "correct id for pushSync" );
        [ [1,"OFO"],[2,"BONGLO"],[3,"BAR"],[4,""],[5,"PUSHED"] ]
            .forEach(function(x){ 
                t.equal( store.getRecordSync(x[0]).toString(), x[1] );  });
        sz( 250 );

        t.equal( store.popSync().toString(), "PUSHED" );
        sz( 200 );

        t.equal( store.nextIdSync(), 5, "back to fifth id" );

        [ [1,"OFO"],[2,"BONGLO"],[3,"BAR"],[4,""],[5,""] ]
            .forEach(function(x){ 
                t.equal( store.getRecordSync(x[0]).toString(), x[1] );  });

        testExistingRecordFile( );
    } ); //23 tests so far

    function sz(size,msg) {
        var sz = fs.statSync(path).size;
        t.equal( sz, size, "Filesize is " + size );

    }
    
    function testExistingRecordFile() {
        stores.open( path, 50, function( err, store ) {
            t.equal( store.nextIdSync(), 6, "6th id" );
            t.equal( store.nextIdSync(), 7, "7th id" );
            sz( 350 );
            store.putRecordSync( 4, new Buffer("onion") );
            store.putRecordSync( 6, new Buffer("pEte") );
            [ [1,"OFO"],[2,"BONGLO"],[3,"BAR"],[4,"onion"],[6,"pEte" ] ]
                .forEach(function(x){ 
                    t.equal( store.getRecordSync(x[0]).toString(), x[1] ); });
            fs.unlinkSync( path );
            t.comment( '---------- test async ------------' );
            testAsync();
        } ); // 8 more, so 31 tests
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
            ], // 2 more, so 33 tests
            [ "four more nextid group", 1,2,3,4 ].map( function(x) { return Number( x ) ?  [ getStore, function() { return asyncStore.nextId } ] : x; } ),
            [
                "sixth async group",
                [ getStore,
                  function() { return asyncStore.nextId },
                  function( err, id ) {
                      t.equal( id, 6, "sixth async nextid call" );
                      sz( 300 );
                  }
                ],
            ], // 2 more so 35 tests
            [
                "push and pop test",
                [
                    getStore,
                    function() { return asyncStore.push },
                    function( err, id ) {
                        t.equal( id, 7, "seventh id from push" );
                        t.equal( asyncStore.getRecordSync(7).toString(), "Record 7" );
                        sz( 350 );
                    },
                    "Record 7"
                ]
            ], // 3 more so 38 tests
            [ "Put Records Async", 2, 3, 5 ].map( function( n ) { 
                return Number(n) ?  [ getStore, function() { return asyncStore.putRecord }, function(err,bytesWritten) { t.equal(bytesWritten,1+String("Record " + n).length,"record " + n + " wrote correct number of bytes")}, n, n == 3 ? "Record " + n : new Buffer( "Record " + n ) ] : n;
            } ), // 3 more so 41 tests

            [ "Get Records Async", 2, 3, 5, 7 ].map( function( n ) { 
                return Number(n) ?  [ getStore,function() { return asyncStore.getRecord }, function( err, buff ) {
                    t.equal( buff.toString(), "Record " + n, "Read Record " + n );
                }, n, null ] : n;
            } ),// 4 more so 45 tests

            [ 'final filesize check',
              [ getStore, 
                function() { return asyncStore.getRecord },
                function( err, buff ) { 
                    t.equal( asyncStore.getRecordSync(7).toString(), "Record 7", "record 7 sync" );
                    t.equal( buff.toString(), "Record 7", "Record 7 async" );
                    sz( 350 );
                },
                7, null
              ],
            ], // 3 more so 48
        ] );
    } //testAsync
        
    function testAsyncGroups( testgroups ) {
        _testAsyncGroups( testgroups );
        
        function _testAsyncGroups( groups ) {
            var group = groups.shift();
            var title = group.shift();
            

            var countdown = group.length;

//            console.log( "** Starting GROUP " + title + " with " + countdown + " things" );

            group.map( function( test ) {
                // group = [  [ test-function, callback, params... ] ]
//                console.log( "** Starting TEST " + title );
                var self     = test.shift()();
                var testFun  = test.shift()();
                var callback = test.shift() || function() {};
                test.push( function() {
//                    console.log( "** Test " + title + ' : ' + countdown );
                    callback.apply( self, arguments );
                    if( --countdown == 0 && groups.length > 0 ) {
//                        console.log( "** Done With " + title );
                        _testAsyncGroups( groups );
                    } 
               } );
                testFun.apply( self, test );
            } );
        }
    } //testAsyncGroups
});

