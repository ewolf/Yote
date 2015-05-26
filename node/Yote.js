
module.exports = {
    getRoot : function() {
        return  STORE[1] || Yote();
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
    
    var proxy = Proxy.create( {

        get : function( proxy, name ) {
            if( name === '_y' ) {
                return _yote_info;
            } else if( name === 'push' ) {
                return function( item ) { _yote_data[ _yote_data.length ] = item; };
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
        enumerate: function() {
            var i = 0;
            return {
                next : function() {
                    return i < _yote_data.length ? 
                        { done : false, value : _transOut(_yote_data[i++]) } :
                        { done : true };
                    
                }
            }
        },
        has : function( proxy, prop ) {
            return prop in _yote_data;
        },
        hasOwn : function( proxy, prop ) {
            return prop in _yote_data;
        }
    }, prot );

    _yote_info = { id : (STORE.push(proxy)-1) };

    return proxy;
} // Yote



var STORE = [null]; //so ids start with '1'

var _register = function( thing ) {
    return STORE.push( thing ) - 1;
}

var _transOut = function( val ) {
    if( typeof val !== 'string' && typeof val !== 'number' ) return val;
    if( Number( val ) > 0 )       return STORE[val];
    if( typeof val === 'string' ) return val.substring(1);
}

var _transIn = function( thing ) {
    if( typeof thing === 'object' ) {
        if( thing._y && thing._y.id ) return thing._y.id;
        return Yote( thing )._y.id;
    }
    return 'v' + thing;
}
