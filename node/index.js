/*
 Synopsis :
     var store = require('yote')
     store.getRoot( rootDirectory, 
                    function( root ) {
                       root.set('some-str', "foo");
                       root.set('some-obj', store.newObj() );
  1                     root.set('some-hash', { ... } );
                       root.set('some-list', [ ... ] );
                       root.get( 'has-default?' ); // --> undefined
                       root.get( 'has-default?', 'yes I has' ); // --> 'yes I has'
                    } );

TODO : new takes args for data and for functions?
*/

module.exports = new YoteStore();

function YoteStore () {
    if(!(this instanceof YoteStore)) return new YoteStore();
}

YoteStore.prototype.getRoot = function() {
    return STORE[1] || new YoteObj();
};

YoteStore.prototype.newObj = function() {
    return new YoteObj();
}


function YoteObj () {
    var self = this;
    if(!(this instanceof YoteObj)) return _transOut( _register(new YoteObj() ) );
    self._d = {};
}

var STORE = [null];

var _register = function( thing ) {
    return STORE.push( thing ) - 1;
}

var _fetch = function( id ) {
    return STORE[ id ];
}

var _transOut = function( val ) {
    if( Number.isNumber( val ) ) return val;

    return val.substring(1);
}

var _transIn = function( thing ) {
    if( typeof thing === 'object' ) {
        if( thing._y && thing._y.id ) return thing._y.id;
        var id = _register( thing );
        thing._y = { 'id' : id, 'dirty' : true };
    }
    return 'v' + thing;
}

YoteObj.prototype.get = function( key, defVal ) {
    var val = this._d[ key ];

    if( typeof val !== 'undefined' ) {
        return _transOut( val );
    }

    this._d[ key ] = _transIn(defVal);
    return defVal;
};
YoteObj.prototype.set = function( key, val ) {
    this._d[ key ] = _transIn(val);
    return val;
};
