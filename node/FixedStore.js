
var fs = require('fs');

module.exports = {
    open: function( path, size, cb ) {
        
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
                  next_id: function() {
                  
                  },
                */

                getRecord: function( index, buffer, cb ) {
                    if( ! buffer ) buffer = new Buffer( size );
                    fs.read( fd, buffer, 0, size, size*index, function( err,bytesRead, buffer ) {
                        cb( err, buffer );
                    } );
                },

                putRecord: function( index, buffer, cb ) {
                    var fillSize = size > buffer.length ? buffer.length : size;
                    fs.write( fd, buffer, 0, fillSize, size*index, function( err, bytesWritten, buffer ) {
                        cb( err, buffer );
                    } );
                },

                numberOfEntries: function( cb ) {
                    fs.stat( path, function( err, stats ) {
                        if( err ) return cb( err );
                        cb( null, parseInt( stats.size / size ) );
                    } )
                },

                nextId: function( cb ) {
                    process.nextTick( function() { 
                        var next_id;
                        (next_id = parseInt( fs.statSync( path ).size / size ) + 1 ) && this.putRecordSync( next_id, '' ) && cb( next_id );
                        cb( next_id );
                    }  );
                },

                getRecordSync: function( index, buffer ) {
                    if( ! buffer ) buffer = new Buffer( size );
                    fs.readSync( fd, buffer, 0, size, size*(index-1) );
                    var len = buffer.toString().indexOf( '\0' );
                    buffer.length = len > 0 ? len : buffer.length;
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
                    var next_id;
                    var b = new Buffer(size); b.write( '' );
                    console.log( fs.statSync(path) );
                    (next_id = parseInt( fs.statSync( path ).size / size ) + 1 ) && this.putRecordSync( next_id, b );
                    return next_id;
                },

            };
            cb( null, store );
        } ); //filesystem call/back
    }, //open
};
