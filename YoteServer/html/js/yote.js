var yote = {
    fetch_root : function() {
        throw new Error("init must be called before fetch_root");
    }
};
    
yote.init = function( yoteServerURL ) {
    // cache storing objects and their meta-data
    var class2meths = {};
    var id2obj = {};

    // returns an object, either the cache or server
    var fetch = function( id ) {
        return id2obj[ id ] || this.root.fetch( id );
    }

    var token;
    
    // creates a proxy method that contacts the server and
    // returns data
    var makeMethod = function( mName ) {
        var nm = '' + mName;
        return function( data, isAsync, sucHandler, failHandler ) {
            var id = this.id;
            return contact( id, nm, data, isAsync, sucHandler, failHandler );
        };
    };

    // method for making async method calls as well?


    // method for translating and storing the objects
    function makeObj = function( datastructure ) {
        /* method that returns the value of the given field on the yote obj */
        var obj = id2obj[ datastructure.id ];
        if( ! obj ) {
            obj = {};
            id2obj[ datastructure.id ] = obj;
        }
        obj.get = function( key ) {
            var val = this.data[key];
            if( val.startsWith( 'v' ) ) {
                return val.substring( 1 );
            } 
            return fetch( val );
        };
        
        var mnames = class2meths[ datastructure.cls ] || [];
        mnames.forEach( function( mname ) {
            obj[ mname ] = makeMethod( mname );
        } );
    } //makeObj
    
    // yote objects can be stored here, and interpreting
    // etc can be done here, the get & stuff

    var returnVal = '';
    var reqListener = function(sucHandfler,failHandler) {
        return function() {
            var res = JSON.parse( this.responseText || '[]' );
        
            // 3 parts : methods, updates and result
            
            // methods
            for( var cls in res.methods ) {
                class2meths[cls] = res.methods[ cls ];
            }
            
            // updates
            res.updates.forEach( function( upd ) {
                makeObj( upd );
            } ); //updates section
            
            // results
            var returns = [];
            res.result.forEach( function( ret ) {
                if( ret.startsWith( 'v' ) ) {
                    returns.push( ret.substring(1) );
                } else {
                    returns.push( fetch( ret ) );
                }
            } );
            returnVal = returns.length > 1 ? returns : returns[0];
        }
    }; //reqListener
    
    var contact = function(id,action,data,async,sucHandler,failHandler) {
        var oReq = new XMLHttpRequest();
        oReq.addEventListener("load", reqListener(sucHandler,failHandler);

        console.log( 'url : ' + ( yoteServerURL || "http://127.0.0.1:8881" ) + 
                  '/' + id +
                  '/' + ( token ? token : '_' ) + 
                     '/' + action )
        
        oReq.open("POST", ( yoteServerURL || "http://127.0.0.1:8881" ) + 
                  '/' + id +
                  '/' + ( token ? token : '_' ) + 
                  '/' + action, async );
        oReq.send(data ? 'p=' + data.map(function(p) {
            return typeof p === 'object' ? p.id : 'v' + p }).join('&p=') 
                  : undefined );
        return returnVal;
    };
        
    self.contact = contact;

    yote.fetch_root = function() {
        this.root = contact('_', 'fetch_root');
        token = this.root.create_token();
console.log( ["TTTT " + token,this.root ] );
        return this.root;
    };

    yote.translateFromObj = function( objects ) {

    };

    yote.translateToObj = function( data ) {

    };

}; //yote.init
