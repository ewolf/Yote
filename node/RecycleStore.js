
var fixed = require('./FixedStore.js');

module.exports = {
    open: function( path, size, callBack ) {
        fixed.open( path, size, function(err,store) {
            if( err ) return cb( callBack );
            fixed.open( path + '.recycle', 40, function(err,recycler) {
                if( err ) return cb( callBack );

                store.delete = function( idx, doPurge, cb ) {
                    if( typeof doPurge === 'function' ) {
                        cb = doPurge;
                        doPurge = false;
                    }
                    recycler.hasRecord( idx, function( err, has ) {
                        if( err ) return cb( err );
                        if( ! has ) {
                            recycler.push( idx, function(err,val) {
                                if( err ) return cb( err );
                                if( doPurge ) {
                                    store.putRecord( idx, '', function( err, could ) { cb( err, true ); } );
                                } else {
                                    cb( null, true );
                                }
                            } );
                        } else {
                            if( doPurge ) {
                                store.putRecord( idx, '', function( err, could ) { cb( err, false ); } );
                            } else {
                                cb( null, false );
                            }
                        }
                    } );
                };
                store.getRecycledIds = function( cb ) {
                    var ids = [];
                    var entries = recycler.numberOfEntries( function(err, entries) {
                        if( err ) return cb( err );
console.log( "Got " + entries + " ----------------- " )
                        if( entries === 0 ) return cb( null, ids );
                        for( var i=1; i <= entries; i++ ) {
                            var rId = recycler.getRecordSync(i);
                            ids.push( parseInt(String(rId)) );
                            if( ids.length === entries ) {
                                cb( null, ids );
                            }
                        }
                    } );
                };
                var oldNextIdFun = store.nextId;
                store.nextId = function( cb ) {
                    recycler.pop( null, function( err, item ) {
                        if( err ) return cb( err );
                        if( item ) { return cb( null, parseInt(String(item)) ); }
                        oldNextIdFun.apply( store, [function( err, id ) {
                            if( err ) return cb( err );
                            cb( null, parseInt(id) );
                        } ] );
                    } );
                },


                store.deleteSync = function( idx, doPurge ) {
                    var has = recycler.hasRecordSync( idx );
                    if( ! has ) {
                        recycler.pushSync( idx );
                    }
                    if( doPurge ) {
                        store.putRecordSync( idx, '' );
                    }
                    return ! has;
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
                    return parseInt( Buffer.isBuffer( recycledId ) ? recycledId.toString() : oldNextIdSyncFun.apply(store,[]) );
                }
                callBack( null, store );
            } );
        } );
    } //open
};
