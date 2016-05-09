function woof() {
    return "OOF";
}

yote_worker = {
    _dirty : {},
    dirty : function(o) {
        _dirty[o._id] = o;
        if( this.updates ) {
            this.updates[o._id] = o;
        }
    }, //dirty
    isYoteObj : function(o) { return typeof o === 'object' && o._id; }, // TODO : better check
    fetch_root : function() {
        parseInt( localStorage.getItem( "maxid" ) ) > 0 || localStorage.setItem( "maxid", 1 );
        var root = this.fetch( 1 );
        if( ! root ) {
            root = this._newobj();
            root._id = 1;
            this.dirty( root );
        }
        return obj;
    },
    fetch     : function( id ) {
        if( _dirty[id] ) {
            return _dirty[id];
        }
        // sql query here
        var json = localStorage.getItem( id + '' );
        if( json ) {
            json = JSON.parse( json );
            var obj = this._newobj( json.s );
            obj._data    = json.d;
            return obj;
        }
    }, //fetch
    stowAll : function() {
        for( var key in this._dirty ) {
            this._dirty[ key ]._stow();
        }
        this._dirty = {};
    }, //stowAll
    newobj : function( stamp ) {
        var obj = this._newobj();
        var idx;
        (idx = (1 + (localStorage.getItem( "maxid" )||0)) ) && localStorage.setItem( "maxid", idx );
        obj._id = idx;
        this.dirty( obj );
        if( stamp ) {
            obj._stamp = stamp;
            yote_worker.stamp( stamp, obj );
        }
        return obj;
    }, //newobj
    _newlist : function() {
        return this.stamp( '_list', this._newobj() );
    }, //_newlist
    _newobj : function() {
        return {
            _yoteobj : true,
            _store : this,
            _data  : {},
            _id    : undefined,
            _stow  : function() {
                localStorage.setItem( this._id, JSON.stringify( {
                    s : this._stamp,
                    d : this._data
                } ) );
            }, //stow
            add_to : function( key, val ) {
                var l = this.get( key );
                if( l && ! Array.isArray( l ) ) {
                    throw new Error( "Tried to add to a non-array" );
                }
                if( ! l ) {
                    l = yote_worker._newlist();
                    
                }
            },
            set    : function( key, val ) { //TODO - injest val?
                var oldval = this.get( key );
                if( oldval != val ) {
                    this._store.dirty( this );
                }
                if( typeof val === 'object' ) {
                    if( ! yote_worker.isYoteObj( item ) ) {
                        throw new Exception( "Error : tried to add non-yote object" );
                    }
                    this._data[ key ] = val._id;
                } else {
                    this._data[ key ] = "v" + val;
                }
                return this.get( key );
            },
            get    : function( key, defval ) {
                if( typeof this._data[ key ] === 'undefined' && typeof defval !== 'undefined' ) {
                    this.set( key, defval );
                }
                var val = this._data[ key ];
                if( val && val.startsWith( 'v' ) ) {
                    return val.substring( 1 );
                } else if( val ) {
                    return this.fetch( val );
                }
                return undefined;
            }
        };
    }, //_newobj
    _stampers = {
        _list : function( obj ) {
            obj._data = [];
            obj.push = function( item ) {
            };
            obj.pop = function() {
            };
            obj.shift = function() {
            };
            obj.unshift = function( item ) {
                
            };
            obj.set = function( key, val ) {
                if( ! isanumber(key ) ) {  //TODO - define this actually
                    console.warn( "Warning, trying to set an array to index '" + key + "'" );
                }
                obj._data[ key ] = val; //TODO - injest here
            };
            obj.get = function( key, val ) {
                
            };
        }
    },
    add_to_stampers : function( name, stampfun ) {
        this._stampers[ name ] = stampfun;
    },
    stamp : function( name, obj ) {
        if( ! this._stampers[ name ] ) {
            console.warn( "Warning: stamp '" + name + "' is not registered" );
            return;
        }
        if( obj.stamped && obj.stamped[name] ) {
            console.warn( "Warning: object already is stamped. restamping" );
        }
        obj.stamped = obj.stamped || {};
        obj.stamped[ name ] = true;
        this._stampers[ name ]( obj );
    }, //stamp
    init : function( initFun ) {
        var lyote = this;
        openDatabase('Yote', 'dbversion 1.0', 'javascript yote store', 64*1024, function() {
            lyote.db = this;
            lyote.db.transaction(function (query){
                query.executeSql('CREATE TABLE IF NOT EXISTS Yote (id integer primary key autoincrement, json text)');
            });
            if( initFun ) {
                initFun();
            }
        } );
    } //init
}; //yote_works


function translate_to_text( item ) {
    if( typeof item === 'object' ) { // TODO - verify it is a yote obj
        if( yote_worker.isYoteObj( item ) ) {
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
    yote_worker.init( function() { 
        var port = pe.ports[0];
        port.onmessage = function(e) {
            var target_id = e.data[0]; // _ - for root
            var action    = e.data[1];
            var data      = e.data[2]; // id / action / data
            
            // special combo :  target_id=_ && action=init

            /**
               init_root imports a javascript file with an init function and this
               will call that function.

               This will return the root object and anything that the called init
               returns.
            **/
            yote_worker.updates = {};
            if( action == 'init_root' && target_id == '_' ) {
                // the data will start with a v
                var extra_data;
                if( data && data[0] ) {
                    importScripts( data[0].substring(1) );
                    extra_data = init();
                }
                var resp_data = [ yote_worker.fetch_root() ];
                if( extra_data ) {
                    resp_data.push( extra_data );
                }
                port.postMessage( marshalResponse( resp_data, yote_worker.updates ) );
            } else {
                var obj = yote_worker.fetch( target_id );
                if( obj && obj[action] ) {
                    var res = obj[action]( data );
                    port.postMessage( marshalResponse( res, yote_worker.updates ) );
                } else {
                    // TODO - handle error case
                }
            }
        }
    } //init
} );