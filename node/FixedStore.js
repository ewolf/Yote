
var fs = require('fs');

module.exports = {
    open: function( path, template, size, cb ) {

        // template is an array of types

        //check if this file exists
        try {
            fs.statSync( path );
        } catch( err ) {
            fs.appendFileSync( path, '' );
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
                  next_id: function() {
                  
                  },
                */

                getRecord: function( index ) {
                    
                },

                putRecord: function( index, data ) {
                    
                },

                numberOfEntries: function() {
                    
                },

                nextId: function() {
                    var next_id = this.numberOfEntries() + 1;
                    this.put_record( next_id, [] );
                    return next_id;
                },


                getRecordSync: function( index ) {
                    var b = new Buffer(size);
                    b.length = fs.readSync( fd, b, 0, size, size*index );
                    return JSON.parse( b.toString() );
                },

                putRecordSync: function( index, data ) {
                    var d = JSON.stringify(data);
                    fs.writeSync( fd, new Buffer( d ), 0, d.length, size*index ) );
                },

                numberOfEntriesSync: function() {
                    return Number.parseInt( fs.statSync( path ).size / size );
                },

                nextIdSync: function() {
                    var next_id = this.numberOfEntries() + 1;
                    this.putRecordSync( next_id, [] );
                    return next_id;
                },




            };
            cb( null, store );
        } ); //filesystem call/back
    }, //open
};
