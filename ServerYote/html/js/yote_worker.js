/*
  yote_worker.addToStamps
  yote_worker.fetch
  
*/

console.log( "IN WORKER LOADING" );
// the exception is so that things can easily be wrapped inside a onReady sort of thing
yote_worker = { init : function() { throw new Error("yote_worker not yet loaded"); } };
yote_worker.init = function() {
    var root;

    var _id2obj, _stamps, _stamp_methods, _maxid = 0;


    function _check( obj ) {
        if( obj === null || obj === undefined ) {
            return undefined;
        }
        if( typeof obj === 'object' ) {
            if( _id2obj[ obj.id ] !== obj ) {
                throw new Error( "Tried to set a non-yote object" );
            }
            return obj.id;
        }
        return 'v' + obj;
    } //_check

    function _arrayInt( n ) {
        if( isNaN( n ) ) {
            console.warn( "arrayInt cannot make '" + n + "' into int, using 0" );
            return 0;
        }
        var num = parseInt(n);
        if( parseFloat(n) !== num ) {
            console.warn( "arrayInt converting " + n + " to " + num );
        }
        return num;
    } //_arrayInt

    _id2obj = {};

    function syncFromServer() {
        var url = '/login/yfrom';
        var synctime = root.get( 'ysyn' );
        yote_worker.contact( url, 'POST', 'ysyn=' + synctime, function( data ) {
            var json = JSON.parse( data );
            // list with the first as sync time
            var line, id, stamps, data, obj;
            for( var i=0,len=json.length; i<len; i++ ) {
                line = json[i];
                id     = line[0];
                if( id > _maxid ) {
                    _maxid = id;
                }
                stamps = line[1];
                data   = line[2];
                obj = _makeBaseObj( id );
                stamps = stamps || [];
                for( var i=0, len=stamps.length; i<len; i++ ) {
                    _stamp( stamps[i], obj );
                }
                _dirty( id, obj, true );
            }
            
        } );
                          
    } //syncFromServer

    function syncToServer() {
        var toSync;
        toSync = _remoteStoreDirty;
        _remoteStoreDirty = {};
        var syncList = [];
        for( var key in toSync ) {
            var ts = toSync[key];
            syncList.push( [ ts.id, ts._stamps, ts._data ] );
        }
        var json = JSON.stringify( syncList );
        var url = '/login/yto';
        yote_worker.contact( url, 'POST', 'y=' + encodeURIComponent(json), function( data ) {
            var json = JSON.parse( data );
            root.set( 'ysyn', json[0] );
        } );
    }
    
    var _synctime, _remoteStoreDirty = {};
    function _dirty( idx, obj, fromRemoteStore ) {
        if( fromRemoteStore !== true ) {
            _remoteStoreDirty[idx] = obj;
        }
        for( var key in _callerDirties ) {
            _callerDirties[ key ][idx] = obj;
        };

        // goofy logic to make it atomic
//        ( window.clearTimeout( _synctime ) && false ) || _synctime = window.setTimeout( syncToServer, 60000 ); //sync every minute? 
    }

    _stamp_methods = {
        _list_container : [ 'calculate', 'add_entry', 'remove_entry' ],
        _list : [ 'sort', 'push', 'splice', 'pop', 'shift', 'unshift' ],
    }; //_stamp_methods
    
    _stamps = {
        '_list_container' : function( obj ) {
            obj._list_container_stamp_names = {};
            obj.calculate = function(/* arguments */) { };
            obj.remove_entry = function( args ) {
                var listName = args[0], entry = args[1];
                this.remove_from( listName, entry );
                this.calculate( 'removed_entry' );
            };
            obj.old_add_to = obj.add_to;
            obj.old_remove_from = obj.remove_from;
            obj.add_to = function( listname, objs ) {
                var res = this.old_add_to( listname, objs );
                this.calculate();
                return res;
            };
            obj.remove_from = function( listname, objs ) {
                var res = this.old_remove_from( listname, objs );
                this.calculate();
                return res;
            };
            obj.add_entry = function( args ) {
                var listName = args[0], entry = args[1];
                if( ! entry ) {
                    entry = root.newobj( this._list_container_stamp_names[listName] || '_list_container');
                }
                var count = this.add_to( listName, entry );
                entry.get( 'name', 'item ' + count );
                entry.set( 'parent', this );
                entry.calculate( 'added_to_list' );
                this.calculate( 'new_entry' );
                return entry;
            };
        }, //_list_container
        '_list' : function( obj ) {
            if( ! Array.isArray( obj._data ) ) {
                obj._data = [];
            }

            obj.toArray = function() {
                var out = [];
                for( var i=0,len=this.length(); i<len; i++ ) {
                    out.push( this.get( i ) );
                }
                return out;
            };

            obj.each = function( fun ) {
                var out = [];
                for( var i=0,len=this.length(); i<len; i++ ) {
                    var val = this.get(i);
                    fun( val, i );
                }
                return this;
            }

            obj.length = function() {
                return obj._data.length;
            };
            obj.sort = function(fun) {
                var ret = obj._data.sort(fun);
                this.fireAllUpdateListeners("sort");
                _dirty( this.id, this );
                return ret;
            };
            obj.push = function( /* items or single array of items */ ) {
                var l = obj._data;
                var items = arguments.length === 1 && Array.isArray( arguments[0] ) ? arguments[0] : arguments;
                for( var i=0, len = items.length; i<len; i++ ) {
                    l.push( _check( items[i] ) );
                }
                this.fireAllUpdateListeners("push");
                _dirty( this.id, this );
                return l.length;
            };
            obj.splice = function( /* start, deletecount, items ... (or single array of items)  */  ) {
                var start = arguments[0];
                var delcount = arguments[1];
                var args = [start,delcount];
                if( arguments.length == 3 && Array.isArray( arguments[2] ) ) {
                    var arry = arguments[2];
                    for( var i=0,len=arry.length; i<len; i++ ) {
                        args.push( arry[i] );
                    }
                } else {
                    for( i=2,len=arguments.length; i<len; i++ ) {
                        args.push( _check(arguments[i]) );
                    }
                }
                var res = obj._data.splice.apply( obj._data, args );
                this.fireAllUpdateListeners("splice");
                _dirty( this.id, this );
                return res;
            };
            obj.pop = function() {
                var res = obj._data.pop();
                this.fireAllUpdateListeners("pop");
                _dirty( this.id, this );
                return res;
            };
            obj.shift = function() {
                var ret = obj._data.shift();
                this.fireAllUpdateListeners("shift");
                _dirty( this.id, this );
                return ret;
            };
            obj.unshift = function( /* items or single array of items */ ) {
                var l = obj._data;
                var items = arguments.length === 1 && Array.isArray( arguments[0] ) ? arguments[0] : arguments;
                for( var i=0, len = items.length; i<len; i++ ) {
                    l.unshift( _check( items[i] ) );
                }
                this.fireAllUpdateListeners("unshift");
                _dirty( this.id, this );
                return l.length;
            };
            obj._oldset = obj.set;
            obj._oldget = obj.get;
            obj.set = function( key, val ) {
                return this._oldset( _arrayInt(key), val );
            };
            obj.get = function( key, initialVal ) {
                return this._oldget( _arrayInt(key), initialVal );
            };
            return obj;
        },
        '_yote_root' : function( obj ) {
            var that = obj;

            obj.init = function() {
                return "XX";
            };

            
            obj.newlist = function( initial_list ) {
                return that.newobj( '_list', initial_list );
            }; //yote_worker.newlist
            
            obj.newobj = function(stamps,startdata) {
                var idx = ++_maxid;
                var newobj = _makeBaseObj(idx);
                stamps = Array.isArray( stamps ) ? stamps : stamps ? [ stamps ] : [];
                for( var i=0, len=stamps.length; i<len; i++ ) {
                    var sname = stamps[i];
                    if( Array.isArray( sname ) ) {
                        for( var j=0, len2 = sname.length; j<len2; j++ ) {
                            _stamp( sname[j], newobj );
                        }
                    } else {
                        _stamp( sname, newobj );
                    }
                }
                if( typeof startdata === 'object' ) {
                    for( var key in startdata ) {
                        var val = _check( startdata[key] );
                        if( val !== undefined ) {
                            newobj._data[key] = val;
                        }
                    }
                }
                _dirty( idx, newobj );
                return newobj;
            }; //yote_worker.newobj
            return obj;
        }
    }; //_stamps

    yote_worker.addToStamps = function( name, fun, methods ) {
        _stamps[ name ] = fun;
        _stamp_methods[ name ] = methods;
    };

    function _stamp( stampname, obj ) {
        _check( obj );
        obj._stamps.push( stampname );
        var stampfun = _stamps[ stampname ];
        if( stampfun ) {
            stampfun( obj );
        } else {
            console.warn( "No stamp function for '" + stampname + "'" );
        }
        return obj;
    } //_stamp


    function _makeBaseObj( id ) { //returns base object
        var obj = {
            id   : id,
            _data : {},
            _stamps : [],
            add_to : function( listname, objs ) {
                var list = this.get( listname );
                if( list && ! list.push ) {
                    throw new Error( "Tried to add to a non-array" );
                }
                if( ! list ) {
                    list = yote_worker.newlist();
                    this.set( listname, list );
                }
                objs = Array.isArray( objs ) ? objs : objs ? [ objs ] : [];

                for( var j=0, jlen = objs.length; j<jlen; j++ ) {
                    list._data.push( _check ( objs[j] ) );
                }
                if( objs.length > 0 ) {
                    _dirty( list.id, list );
                    list.fireAllUpdateListeners("add_to",this,listname,objs);
               }
                return list._data.length;
            },
            remove_from : function( listname, objs ) {
                var list = this.get( listname ), i;
                if( list && ! list.splice ) {
                    console.warn( "Tried to remove from a non existant list" );
                    return;
                }
                var l = list._data;
                var count = 0;
                objs = Array.isArray( objs ) ? objs : objs ? [ objs ] : [];
                for( var j=0, jlen = objs.length; j<jlen; j++ ) {
                    var ostring = _check ( objs[j] );
                    for( var i=0, len=l.length; i<len; i++ ) {
                        if( l[i] === ostring ) {
                            l.splice( i, 1 );
                            count++;
                        }
                    }
                }
                if( count > 0 ) {
                    _dirty( list.id, list );
                    list.fireAllUpdateListeners("remove_from",this,listname,objs);
                }
                return count;
            },
            get : function( key, initialVal ) {
                var d = this._data[ key ];
                if( d === undefined && initialVal !== undefined ) {
                    if( typeof initialVal === 'function' ) {
                        // the purpose of this is to allow for
                        // default yote object be able to be used
                        // as defaults without having to create them
                        // otherwise
                        initialVal = initialVal(); 
                    }
                    this.set( key, initialVal );
                    return initialVal;
                }
                if( typeof d === 'string' && d.startsWith('v') ) {
                    return d.substring(1);
                }
                d = parseInt( d );
                if( d > 0 ) {
                    return _fetch( d );
                }
                return undefined;
            },
            set : function( key, val ) {
                var oldval = this.get( key );
                this._data[ key ] = _check( val );
                if( val !== oldval ) {
                    _dirty( this.id, this );
                    this.fireAllUpdateListeners("set",key,val);
                }
                return val;
            },
            update : function( updates ) {
                var key, val;
                // unlike set, this takes in keyparis and updates that way
                // using update causes the listners to fire
                
                if( Array.isArray( updates ) ) {
                    for( var i=0, len=updates.length; i<len; i++ ) {
                        var upd = updates[i];
                        for( key in upd ) {
                            val = upd[ key ];
                            this._data[ key ] = _check( val );
                        }
                    }
                } else { // TODO : maybe upgrade yote.ui.js to be able to handle this
                    for( key in updates ) {
                        val = updates[ key ];
                        this._data[ key ] = _check( val );
                    }
                }

                this.fireAllUpdateListeners("update",updates);
                _dirty( this.id, this );
                return this;
            }, //update
            _listeners : {},
            addUpdateListener : function( fun, tag ) {
                tag = tag || '_';
                this._listeners[ tag ] = fun;
            },
            fireAllUpdateListeners : function(/* arguments */) {
                var tag;
                for( tag in this._listeners ) {
                    this._listeners[tag]( this, arguments );
                }
            },
            fireUpdateListener : function( tag, msg ) {
                var listener = this._listeners[ tag ];
                if( listener ) {
                    listener( this, msg );
                } else {
                    console.warn( "No listeners for '" + tag + "'" );
                }
            }
        };
        if( id ) {
            _id2obj[ id ] = obj;
        }
        return obj;
    } //_makeBaseObj

    // returns an object, either the cache or server
    function _fetch( id ) {
        var obj = _id2obj[ id ], i, len;
        return obj;
    } //_fetch

    // ----------- PUBLIC FUN

    yote_worker.fetch = _fetch;

    yote_worker.fetch_root = function() {
        return _fetch( 1 ) || _stamp( '_yote_root', _makeBaseObj(1) );
    }; //yote_worker.fetch_root

    yote_worker.contact = function( url, proto, data, fun ) {
        var oReq = new XMLHttpRequest();
        oReq.addEventListener("loadend", function() {
            fun( oReq.responseText );
        } );
        oReq.addEventListener("error", function(e) { console.log( e ); if(true)alert('error : ' + e) } );
        oReq.addEventListener("abort", function(e) { console.log( e ); if(true)alert('abort : ' + e) } );
        
        console.log( "CONTACTING SERVER ASYNC via url : " + url );
        
        oReq.open( proto, url, true );
        if( data ) {
            oReq.send( data );
        } else {
            oReq.send();
        }
    }; //yote_worker.contact


    // where syncFromServer would be called
    
    // ensure a root exists
    yote_worker.fetch_root();
    
}; //yote.init

yote_worker.init();


//web worker
onconnect = function(e) {
    console.log( "Worker got req" );

    var port = e.ports[0];

    var _callerDirties = {};
    
    port.addEventListener('message', function( e ) {
        try {
        var key  = e.data[0];
        var args = e.data[1];
        
        var id        = args[0];
        var method    = args[1];
        var call_args = args[2];
        
        var obj = yote_worker.fetch( id );
        if( obj[ method ] ) {
            // note everything that has changed since
            // this was called in order to build update
            var dirties = {};
            _callerDirties[ key ] = dirties;
            var result = obj[ method ]( call_args );
            delete _callerDirties[ key ];

            var updates = [];
            var methods = {};
            for( var id in dirties ) {
                var upobj = dirties[id];
                updates.push( [ upobj.id, upobj._stamps, upobj._data ] );
                var stamps = upobj._stamps;
                for( var i=0, len = stamps.length; i<len; i++ ) {
                    var stamp = stamps[i];
                    methods[ stamp ] = _stamp_methods[ stamp ];
                }
            };
            
            var ret = [ key, result, updates, methods ];
            port.postMessage( ret );
        } else {
            // TODO - error response
            console.warn( "ERROR: ERROR: object method requested not found" );
            port.postMessage( "BDDY" );
        }
        }catch(err) { port.postMessage( "ER " + err ); }
    } );
    root = yote_worker.fetch_root();
    importScripts( '/__/js/foo.js' );
    port.start();
} 
console.log( "yote_worker load" );
