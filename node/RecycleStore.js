
var fixed = require('./FixedStore.js');

module.exports = {
    open: function( path, size, callBack ) {
        fixed.open( path, size, function(err,store) {
            if( err ) return cb( callBack );
            fixed.open( path + '.recycle', size, function(err,recycler) {
                if( err ) return cb( callBack );
                store.delete = function( idx, doPurge, cb ) {
                    recycler.push( idx, function(err) {
                        if( err ) return cb( err );
                        if( doPurge ) {
                            return store.putRecord( idx, '', cb );
                        }
                        cb( null, true );
                    } );
                };
                store.getRecycledIds = function( cb ) {
                    var ids = [];
                    var entries = recycler.numberOfEntries( function(entries) {
                        for( var i=1; i <= entries; i++ ) {
                            recycler.getRecordSync(i,function( err, rId ) {
                                if( err ) return cb( err );
                                ids.push( rId );
                                if( ids.length === entries ) {
                                    cb( null, ids );
                                }
                            } );
                        }
                    } );
                };
                var oldNextIdFun = store.nextId;
                store.nextId = function( cb ) {
                    recycler.pop( null, function( err, item ) {
                        if( err ) return cb( err );
                        if( item ) { return cb( null, String(item) ); }
                        oldNextIdFun.apply( store, [function( err, id ) {
                            if( err ) return cb( err );
                            cb( null, id );
                        } ] );
                    } );
                },


                store.deleteSync = function( idx, doPurge ) {
                    if( recycler.hasRecordSync( idx ) ) {
                        console.log( "BLSLSLSLS" );
                    }
                    recycler.pushSync( idx );
                    if( doPurge ) {
                        store.putRecordSync( idx, '' );
                    }
                };
                store.getRecycledIdsSync = function() {
                    var ids = [];
                    var entries = recycler.numberOfEntriesSync();
                    for( var i=1; i <= entries; i++ ) {
                        ids.push( Number(recycler.getRecordSync(i)) );
                    }
                    return ids;
                };
                var oldNextIdSyncFun = store.nextIdSync;
                store.nextIdSync = function() {
                    var recycledId = recycler.popSync();
                    return Buffer.isBuffer( recycledId ) ? recycledId.toString() : oldNextIdSyncFun.apply(store,[]);
                }
                callBack( null, store );
            } );
        } );
    } //open
};
