/*
 Synopsis :
     var store = require('yote')
     store.getRoot( rootDirectory, 
                    function( root ) {
                       root.set('some-str', "foo");
                       root.set('some-obj', store.newObj() );
                       root.set('some-hash', { ... } );
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
    if(!(this instanceof YoteObj)) return new YoteObj();
    self._d = {};
    _transIn( self );
}

var STORE = [null];

var _register = function( thing ) {
    return STORE.push( thing ) - 1;
}

var _fetch = function( id ) {
    return STORE[ id ];
}

var _transOut = function( val ) {
    if( Number( val ) > 0 ) return STORE[val];

    return val.substring(1);
}

var _transIn = function( thing ) {
    if( typeof thing === 'object' ) {
        if( thing._y && thing._y.id ) return thing._y.id;
        var id = _register( thing );
        thing._y = { 'id' : id, 'dirty' : true };
        return id;
    }
    return 'v' + thing;
}

YoteObj.prototype.get = function( key, defVal ) {
    var val = this._d[ key ];
    if( typeof val !== 'undefined' ) {
        return _transOut( val );
    }

    this._d[ key ] = _transIn(defVal);
    this._y.dirty = true;
    return defVal;
};
YoteObj.prototype.set = function( key, val ) {
    var val = _transIn(val);
    this._y.dirty = val === this._d[ key ];
    this._d[ key ] = val;
    return val;
};
/*

Proxies
[1G[0J> [3Gvar _p = {}; var p = Proxy.create({ set: function(proxy,name,val) { _p[name] = val; }, get: function(proxy,name) { return _p[name].toUpperCase() } } );
var _p = {}; var p = Proxy.create({ set: function(proxy,name,val) { _p[name] = val; }, get: function(proxy,name) { return _p[name].toUpperCase() } } );
undefined
[1G[0J> [3Gp.foo = 'bar';
p.foo = 'bar';
'bar'
[1G[0J> [3Gp.foo
p.foo
'BAR'
[1G[0J> [3G

*/
