var test = require('tape');
var fs = require('fs');

var stores = require( './FixedStore' );

var path = '/tmp/foo';
try { fs.unlinkSync( path ); } catch(e){}

test( 'new record file', function(t) {
    t.plan(52);

    var size = 50;

    var longstr = (function() { var str = ''; for(var i=0;i<size; i++ ) { str += 'x' } return str; })();

    var toolongstr = (function() { var str = ''; for(var i=0;i<=size; i++ ) { str += 'x' } return str; })();

    stores.open( path, size, function( err, store ) {
        t.equal( store.popSync(), undefined, "empty pop" );

        t.equal( store.nextIdSync(), 1, "first id" );
        sz( size );
        t.equal( store.nextIdSync(), 2, "second id" );
        sz( 2*size );
        t.equal( store.nextIdSync(), 3, "third id" );
        sz( 3*size );
        t.equal( store.nextIdSync(), 4, "fourth id" );
        sz( 4*size );


        store.putRecordSync( 1, new Buffer("FOO") );
        store.putRecordSync( 3, "BAR" );
        store.putRecordSync( 2, new Buffer(longstr) );
        store.putRecordSync( 1, new Buffer("OFO") );
        t.equal( store.pushSync( new Buffer("PUSHED") ), 5, "correct id for pushSync" );
        [ [1,"OFO"],[2,longstr],[3,"BAR"],[4,""],[5,"PUSHED"] ]
            .forEach(function(x){ 
                t.equal( store.getRecordSync(x[0]).toString(), x[1] );  });
        sz( 5*size );

        t.equal( store.popSync().toString(), "PUSHED" );
        sz( 4*size );

        t.equal( store.nextIdSync(), 5, "back to fifth id" );

        [ [1,"OFO"],[2,longstr],[3,"BAR"],[4,""],[5,""] ]
            .forEach(function(x){ 
                t.equal( store.getRecordSync(x[0]).toString(), x[1] );  });

        testExistingRecordFile( );
    } ); //24 tests so far

    function sz(size,msg) {
        var sz = fs.statSync(path).size;
        t.equal( sz, size, "Filesize is " + size );

    }
    
    function testExistingRecordFile() {
        stores.open( path, 50, function( err, store ) {
            t.equal( store.nextIdSync(), 6, "6th id" );
            t.equal( store.nextIdSync(), 7, "7th id" );
            sz( 7*size );
            store.putRecordSync( 4, new Buffer("onion") );
            store.putRecordSync( 6, new Buffer("pEte") );
            [ [1,"OFO"],[2,longstr],[3,"BAR"],[4,"onion"],[6,"pEte" ] ]
                .forEach(function(x){ 
                    t.equal( store.getRecordSync(x[0]).toString(), x[1] ); });

            t.throws( function() { store.pushSync( new Buffer( toolongstr ) ) } );

            fs.unlinkSync( path );
            t.comment( '---------- test async ------------' );
            testAsync();
        } ); // 9 more, so 31 tests
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
                  }, path, size 
                ],
            ],
            [
                "empty pop",
                [ getStore,
                  function() { return asyncStore.pop },
                  function( err, val ) {
                      t.equal( val, undefined, "undefined return from pop" );
                      sz( 0 );
                  },
                  null //for buffer
                ],
            ], // 2 more, so 33 tests
            [
                "first nextid group",
                [ getStore,
                  function() { return asyncStore.nextId },
                  function( err, id ) {
                      t.equal( id, 1, "first async nextid call" );
                      sz( size );
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
                      sz( 6*size );
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
                        sz( 7*size );
                    },
                    "Record 7"
                ]
            ], // 3 more so 38 tests
            [ "Put Records Async", 2, 3, 5 ].map( function( n ) { 
                return Number(n) ?  [ getStore, function() { return asyncStore.putRecord }, function(err,bytesWritten) { t.equal(bytesWritten,1+String("Record " + n).length,"record " + n + " wrote correct number of bytes")}, n, new Buffer( "Record " + n ) ] : n;
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
                    sz( 7*size );
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

