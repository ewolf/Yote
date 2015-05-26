
var fs = require('fs');

module.exports = {
    open: function( path, size, cb ) {
        try { 
            fs.statSync( path );
        } catch( err ) {
            fs.writeFileSync( path, "" );
        }

        fs.open( path, 'r+', function( err, fd ) {
            if( err ) {
                return cb( err );
            }
            
            var store = {
                /*
                  unlink: function() {},
                  size:   function() { return size; },
                  push:   function(record) { //adds record to the end of the store
                  
                  },
                  empty:  function() {},
                  ensure_entry_count : function( coune ) {
                  },
                  nextId: function() {
                  
                  },
                */

                getRecord: function( index, buffer, cb ) {
                    if( ! cb && typeof buffer === 'function' ) { 
                        cb = buffer; 
                        buffer = null; 
                    }
                    if( ! buffer ) buffer = new Buffer( size );
                    fs.read( fd, buffer, 0, size, size*index, function( err,bytesRead, buffer ) {
                        cb( err, buffer, "HA" );
                    } );
                },

                putRecord: function( index, buffer, cb ) {
                    if( ! cb && typeof buffer === 'function' ) { 
                        cb = buffer; 
                        buffer = null; 
                    }
                    console.trace("put record");
                    fs.write( fd, buffer, size*index, function( err, bytesWritten, buffer ) {
                        cb( err, buffer, "BA" );
                    } );
                },

                numberOfEntries: function( cb ) {
                    fs.stat( path, function( err, stats ) {
                        if( err ) return cb( err );
                        cb( null, parseInt( stats.size / size ) );
                    } )
                },

                nextId: function( cb ) {
                    var self = this;
                    process.nextTick( function() { 
                        var nextId;
                        try {
                            nextId = self.nextIdSync();
console.info( "next id callback", nextId, cb + '' );
                            cb( null, nextId );
                        } catch( err ) {
                            cb( err );
                        }
                    }  );
                },
                pop: function(buffer, cb) {
                    //remove the last record and return it
                    process.nextTick( function() {
                        try {
                            var res = self.popSync();
                            return cb( null, res );
                        } catch( err ) {
                            cb( err );
                        }
                    } );
                },
                push: function( buffer, cb ) {
                    var self = this;
                    process.nextTick( function() {
                        try {
                            var ret = self.pushSync( buffer );
                            return cb( null, ret );
                        } catch( err ) { return cb( err ); }
                    } );
                },

// SYNC -------------------------------------

                getRecordSync: function( index, buffer ) {
                    if( ! buffer ) buffer = new Buffer( size );
                    fs.readSync( fd, buffer, 0, size, size*(index-1) );
                    var len = buffer.toString().indexOf( '\0' );
                    buffer.length = len >= 0 ? len : buffer.length;
                    return buffer;
                },

                putRecordSync: function( index, buffer ) {
                    var maxSize = size - 1;
                    var fillSize = maxSize > buffer.length ? buffer.length : maxSize;
                    var wrote = fs.writeSync( fd, buffer, 0, fillSize, size*(index-1) );
                    var nb = Buffer( "\0" );
                    fs.writeSync( fd, nb, 0, nb.length, size*(index-1) + wrote );
                    return wrote + 1;
                },

                numberOfEntriesSync: function() {
                    return Number.parseInt( fs.statSync( path ).size / size );
                },

                nextIdSync: function() {
                    var nextId;
                    (nextId = parseInt( fs.statSync( path ).size / size ) + 1 ) && fs.ftruncateSync( fd, nextId * size );
                    return nextId;
                },
                popSync: function(buffer) {
                    //remove the last record and return it
                    var ret, ents;
                    (ents = this.numberOfEntriesSync()) && 
                        (ret = self.getRecordSync( ents, buffer )) && 
                        fs.ftruncate( fd, size * ( ents - 1 ) );
                    return ret;
                },
                pushSync: function(buffer) {
                    var nextId = self.nextIdSync();
                    return self.putRecordSync( nextId, buffer );
                },
            };
            cb( null, store );
        } ); //filesystem call/back
    }, //open
};
