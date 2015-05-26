function YoteObj (target) {
    if( ! target ) target = {};
    var yote_info = {};
    var yote_data = {};
    var proxy = Proxy( target, { 
        get: function( proxy, name ) {
            if( name === '_y' ) return yote_info;
            return _transOut( yote_data[ name ] );
        },
        set: function( proxy, name, value ) {
            yote_data[ name ] = _transIn( value );
        }
        
    } } );
    yote_data.id = _register( proxy );
    return proxy;
} //YoteStore

YoteObj( {} );
