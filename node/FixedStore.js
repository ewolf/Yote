
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
                getRecord: function( index, buffer, cb ) {
                    if( ! cb && typeof buffer === 'function' ) { 
                        cb = buffer; 
                        buffer = null; 
                    }
                    if( ! buffer ) buffer = new Buffer( size );
                    fs.read( fd, buffer, 0, size, size*(index-1), function( err,bytesRead, buf ) {
                        if( buf ) {
                            var len = buf.toString().indexOf( '\0' );
                            buf.length = len >= 0 ? len : buf.length;
                        }
                        cb( err, buf );
                    } );
                },

                putRecord: function( index, buffer, cb ) {
                    buffer = Buffer.isBuffer( buffer ) ? Buffer.concat( [buffer,new Buffer("\0")],buffer.length+1) : new Buffer( buffer + '\0' ); 
                    fs.write( fd, buffer, 0, buffer.length, size*(index-1), function( err, bytesWritten, buff ) {
                        cb( err, bytesWritten, buff );
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
                            cb( null, nextId );
                        } catch( err ) {
                            cb( err );
                        }
                    }  );
                },
                pop: function(buffer, cb) {
                    var self = this;
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
                    buffer = buffer ? String(buffer) : '';
                    var maxSize = size - 1;
                    var fillSize = maxSize > buffer.length ? buffer.length : maxSize;
                    var wrote = fs.writeSync( fd, Buffer.concat( [Buffer.isBuffer(buffer) ? buffer : new Buffer(buffer), new Buffer("\0")], buffer.length + 1 ), 0, fillSize, size*(index-1) );
                    return wrote;
                },

                numberOfEntriesSync: function() {
                    return parseInt( fs.statSync( path ).size / size );
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
                        ents > 0 && ( ret = this.getRecordSync( ents, buffer )) && 
                        fs.ftruncateSync( fd, size * ( ents - 1 ) );
                    return ret;
                },
                pushSync: function(buffer) {
                    var nextId;
                    (nextId = this.nextIdSync() ) && this.putRecordSync( nextId, buffer );
                    return nextId;
                },
            };
            cb( null, store );
        } ); //filesystem call/back
    }, //open
};
