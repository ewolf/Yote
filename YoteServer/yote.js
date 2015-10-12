var yote = {};

(function() {
    var class2meths = {};
    var id2obj = {};
    
    var makeMethod = function( mName ) {
        var nm = '' + mName;
        return function( data ) {
            var id = this.id;
            return contact( "/" + id + "/" + nm, data );
        };
    };
    
    var fetch = function( id ) {
        return id2obj[ id ];
    }
    
    // yote objects can be stored here, and interpreting
    // etc can be done here, the get & stuff
    var returnVal = '';
    var reqListener = function() {
        var res = JSON.parse( this.responseText || '[]' );
        
        // 3 parts : methods, updates and result
        
        // methods
        for( var cls in res.methods ) {
            class2meths[cls] = res.methods[ cls ];
        }
        
        // updates
        res.updates.forEach( function( upd ) {
            upd.get = function( key ) {
                var val = this.data[key];
                if( val.startsWith( 'v' ) ) {
                    return val.substring( 1 );
                } else {
                    return fetch( val );
                }
            };
            
            var mnames = class2meths[ upd.cls ] || [];
            mnames.forEach( function( mname ) {
                upd[ mname ] = makeMethod( mname );
            } );
            
            id2obj[ upd.id ] = upd;
            
            return upd;
        } ); //updates section
        
        // results
        var returns = [];
        res.result.forEach( function( ret ) {
            if( ret.startsWith( 'v' ) ) {
                returns.push( ret );
            } else {
                returns.push( id2obj[ ret ] );
            }
        } );
        returnVal = returns;
    }; //reqListener
    
    var contact = function(path,data) {
        var oReq = new XMLHttpRequest();
        var async = false;
        oReq.addEventListener("load", reqListener) ;
        oReq.open("POST", "http://127.0.0.1:8881" + path, async );
        oReq.send(data ? 
                  'p=' + data.map(function(p) { return typeof p === 'object' ? p.id : 'v' + p }).join('&p=') 
                  : undefined );
        return returnVal;
    };
    
    var contactOne = function(path,data) {
        return contact(path,data)[0];
    };
    
    self.contact = contact;

    yote.fetch_root = function() {
        // fetches the base
        this.base = contactOne("/_/fetch_root");
        return this.base;
    }
} )();

