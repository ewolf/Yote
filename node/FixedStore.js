
var fs = require('fs');



module.exports = {
    openSync: function( path, size, cb ) {
        //check if this file exists
        try {
            fs.statSync( path );
        } catch( err ) {
            fs.appendFileSync( path, '' );
        }
        var fd = fs.openSync( path, 'r+' );
        return create_store( fd, path, size );
    },
    open: function( path, size, cb ) {
        //check if this file exists
        try {
            fs.statSync( path );
        } catch( err ) {
            fs.appendFileSync( path, '' );
        }

        fs.open( path, 'r+', function( err, fd ) {
            if( err ) return cb( err );
            cb( null, create_store( fd, path, size ) );
        } );
    }, //open
};

var create_store = function( fd, path, size ) {
    return {
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

        getRecord: function( index, buffer ) {
            var getSize = buffer.length > size ? size : buffer.length;
            fs.read( fd, buffer, 0, getSize, (index-1)*size, function(err,bytesRead,buffer) {
                if( err ) return cb( err );
                cb( null, bytesRead, buffer );
            } );
        },

        putRecord: function( index, buffer, cb ) {
            var putSize = buffer.length > size ? size : buffer.length;
            fs.write( fd, buffer, 0, putSize, (index-1)*size, function(err,byteswrote,buffer) {
                if( err ) return cb( err );
                cb( null, bytesWrote, buffer );
            } );
        },

        numberOfEntries: function( cb ) {
            fs.stat( path, function( err, stat ) {
                if( err ) return cb( err );
                cb( null, stat.size / size );
            } );
        },

        nextId: function( cb ) {
            Process.nextTick( function() { 
                // the assignment of ids is necessarily a synchronous action
                try {
                    var next_id =this.nextIdSync();
                } catch( err ) {
                    cb( err );
                }
                cb( null, next_id );
            } );
        },


        getRecordSync: function( index, buffer ) {
            if( ! buffer ) buffer = new Buffer(size);
            fs.readSync( fd, buffer, 0, size, size*(index-1) );
            buffer.length = buffer.toString().indexOf( '\u0000' );
            return buffer;
        },

        putRecordSync: function( index, buffer ) {
            var putSize = buffer.length > size ? size : buffer.length;
var wrote =  fs.writeSync( fd, buffer, 0, putSize, size*(index-1) );
console.log( [ 'put',index, size*(index-1),buffer.toString(), putSize, buffer.length, wrote ] );
            return wrote;
        },

        numberOfEntriesSync: function() {
            return Number.parseInt( fs.statSync( path ).size / size );
        },

        nextIdSync: function() {
            var next_id;
            // the following line must be a single statement in order to be sure of correct execution
            (next_id = ( 1 + Number.parseInt( fs.statSync( path ).size / size )) ) && this.putRecordSync( next_id, new Buffer( size ) );

            return next_id;
        }
        
    };
};
