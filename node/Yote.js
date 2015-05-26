
module.exports = {
    getRoot : function() {
        return STORE.fetchRoot();
    },
    translate : function( obj ) {
        return Yote( obj );
    }
};

function Yote( target, suppressWatch ) {
    if( ! target ) {
        target = {};
        suppressWatch = true;
    }
    if( target._y ) return target;

    var _yote_info, _yote_data, prot;

    if( Array.isArray( target ) ) {
        _yote_data = target.map( function( item ) { return _transIn( item ); } );
        prot = Array.prototype;
    } else {
        _yote_data = {};
        for( var key in target ) {
            _yote_data[ key ] = _transIn( target[key] );
        }
        prot = Object.prototype;
    }

    if( ! suppressWatch ) {
        
    }
    var inget = false;
    var proxy = Proxy.create( {

        get : function( proxy, name ) {
            if( name === '_y' ) {
                return _yote_info;
            } else if( name === 'push' ) {
                return function( item ) { _yote_data[ _yote_data.length ] = item; };
            } else if( name === 'nodeName' ) {
                return _yote_data.nodeName;
            } else if( name === 'inspect' ) {
                return _yote_data.inspect;
            } else if( name === 'length' ) {
                return _yote_data.length;
            } else if( name === 'prototype' ) {
                return prot;
            } else if( name === 'copy' ) {
                return _yote_data.copy;
            }
            return _transOut( _yote_data[ name ] );
        },
        set : function( proxy, name, value ) {
            _yote_data[ name ] = _transIn( value );
        },

        keys : function() {
            return Object.keys( _yote_data );
        },
        ownKeys : function() {
            return Object.keys( _yote_data );
        },
        getOwnPropertyDescriptor : function( proxy, name ) {
            if( name == '_y' ) {
                return _yote_info;
            }
            return _transOut( _yote_data[ name ] );
        },
        getOwnPropertyNames : function() {
            return Object.keys( _yote_data );
        },
        enumerate : function() {
            var res = [];
            for( var name in _yote_data ) res.push(name);
            return res;
/*
            console.log( 'ENUM' );console.trace();
            var i = 0;
            return {
                'next' : function() {
                    console.log( "NEXT " + i );
                    return i < _yote_data.length ? 
                        { done : false, value : _transOut(_yote_data[i++]) } :
                        { done : true };
                    
                }
            };
*/
        },
        has : function( name ) {
            return name in _yote_data;
        },
        hasOwn : function( name ) {
            return name in _yote_data;
        }
    }, prot );

    _yote_info = { id : STORE.getId(proxy) };

    return proxy;
} // Yote

var _store = [null]; //first entry starts with index 1
var STORE = {
    fetchRoot: function() {
        return _store[ 1 ] || Yote();
    },
    fetch: function( id ) {
        return _store[ id ];
    },
    getId: function( thing ) {
        return _store.push( thing ) - 1;
    }
};

var _transOut = function( val ) {
    if( typeof val !== 'string' && typeof val !== 'number' ) return val;
    if( Number( val ) > 0 )       return STORE.fetch(val);
    if( typeof val === 'string' ) return val.substring(1);
}

var _transIn = function( thing ) {
    if( typeof thing === 'object' ) {
        if( thing._y && thing._y.id ) return thing._y.id;
        return Yote( thing )._y.id;
    }
    return 'v' + thing;
}
