
var res = ''; // persists, so ya.
var returnVal = '';

var class2meths = {};
var id2obj = {};

var makeMethod = function( mName ) {
    var nm = '' + mName;
    return function( data ) {
        console.log( [ 'DDDDDDDDDDDDDDDDDDD', data ] );
        var id = this.id;
        return contact( "/" + id + "/" + nm, data );
    };
};

var fetch = function( id ) {
    return id2obj[ id ];
}

// yote objects can be stored here, and interpreting
// etc can be done here, the get & stuff
var reqListener = function() {
    res = JSON.parse( this.responseText || '[]' );
console.log( [ this.responseText, res, "QQQ" ] );
    // 200 OK ( {"result":["771"],"updates":[{"class":"Yote::ServerRoot","id":"771","data":{}}],"methods":{"Yote::ServerRoot":["fetch_root","fetch_app","test"]}} )
    
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
console.log( [ 'mmmmmm', mnames ] );
        mnames.forEach( function( mname ) {
console.log( [ 'naaaa', mname ] );
            upd[ mname ] = makeMethod( mname );
        } );

        id2obj[ upd.id ] = upd;
        
        return upd;
    } ); //updates section
    
    // result
    var returns = [];
    res.result.forEach( function( ret ) {
console.log(  'lookup : ' + ret );
        if( ret.startsWith( 'v' ) ) {
            returns.push( ret );
        } else {
console.log( [ 'rrrrrr', ret, id2obj, id2obj[ ret ] ] );
            returns.push( id2obj[ ret ] );
        }
    } );
    console.log( [ 'Retty', returns ] );
    returnVal = returns;
}; //reqListener

var contact = function(path,data) {
    var oReq = new XMLHttpRequest();
    var async = false;
    oReq.addEventListener("load", reqListener) ;
    oReq.open("POST", "http://127.0.0.1:8881" + path, async );
    oReq.send(data);
    return returnVal;
};

var contactOne = function(path,data) {
    return contact(path,data)[0];
};

self.contact = contact;

yote = {
    fetch_root : function() {
        // fetches the base
        console.log( "BBBBBASE" );
        this.base = contactOne("/_/fetch_root");
        console.log( [ "GOT BASE",  this.base ] );
        return this.base;
    }
};

