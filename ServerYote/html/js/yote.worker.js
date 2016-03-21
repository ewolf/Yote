function woof() {
    return "OOF";
}

yote.worker = {
    _dirty : {},
    _isYoteObj : function(o) { return typeof o === 'object' && o._id; } // TODO : better check
};


function translate_to_text( item ) {
    if( typeof item === 'object' ) { // TODO - verify it is a yote obj
        if( yote.worker._isYoteObj( item ) ) {
            return item._id;
        }
        else if( Array.isArray( item ) ) {
            return item.map( function( it ) {
                return translate_to_text( it );
            } );
        } else {
            var ret = {};
            for( var key in item ) {
                ret[ key ] = translate_to_text( item[key] );
            }
            return ret;
        }
    } else {
        return "v" + item;
    }
} //translate_to_text


function marshalResponse( obj ) {
    
    {
        result  => translate_to_text(obj),
        updates => [],
        methods => {}
    };
} //marshalResponse

self.addEventListener('connect', function(pe) { 
    var port = pe.ports[0];
    port.onmessage = function(e) {
        var target_id = e.data[0]; // _ - for root
        var action    = e.data[1];
        var data      = e.data[2]; // id / action / data
        
        // special combo :  target_id=_ && action=init
        if( action == 'init_root' && target_id == '_' ) {
            // the data will start with a v
            importScripts( data[0].substring(1) ); 
            var resp_data = init();
            port.postMessage( [resp_data] );
        } else {
            port.postMessage( ["NOWAY"] );
        }
    }
} );
