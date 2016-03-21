/*
  yote_worker.addToStamps
  yote_worker.fetch
  
*/

// the exception is so that things can easily be wrapped inside a onReady sort of thing
var yote_worker = { init : function() { throw new Error("yote_worker not yet loaded"); } };
yote_worker.init = function() {
    var root;

    var _id2obj, _stamps, _callerDirties = {}, _maxid = 1;

    var _stamp_methods = {
        _list_container : [ 'calculate', 'add_entry', 'remove_entry' ],
        _list : [ 'sort', 'push', 'splice', 'pop', 'shift', 'unshift' ],
        _yote_root  : [ 'init', 'newlist', 'newobj' ]
    }; //_stamp_methods
    

    yote_worker.callerDirties = _callerDirties;
    yote_worker.stamp_methods = _stamp_methods;


    function _check( obj ) {
        if( obj === null || obj === undefined ) {
            return undefined;
        }
        if( typeof obj === 'object' ) {
            if( _id2obj[ obj.id + '' ] !== obj ) {
                throw new Error( "Tried to set a non-yote object @<" + obj.id + "> [" + JSON.stringify(obj) + "] with [ " + JSON.stringify( _id2obj[obj.id+''] ) + "]" );
            }
            return obj.id;
        }
        return 'v' + obj;
    } //_check

    yote_worker.checklist = function( obj ) {
        if( Array.isArray( obj ) ) {
            return obj.map( yote_worker.checklist );
        }
        return _check( obj );
    };

    function _arrayInt( n ) {
        if( isNaN( n ) ) {
//            console.warn( "arrayInt cannot make '" + n + "' into int, using 0" );
            return 0;
        }
        var num = parseInt(n);
        if( parseFloat(n) !== num ) {
//            console.warn( "arrayInt converting " + n + " to " + num );
        }
        return num;
    } //_arrayInt

    _id2obj = {};

    function syncFromServer() {
        var url = '/login/yfrom';
        var synctime = root ? root.get( 'ysyn' ) : 0;
        yote_worker.contact( url, 'POST', 'ysyn=' + synctime, function( data ) {
            if( data ) {
                var json = JSON.parse( data );
                //TODO - include last update times
                loadHistory( json, true );
            }
        } );
                          
    } //syncFromServer

    function loadHistory( history, fromServer ) {
        if( history && Array.isArray( history ) ) {
            for( var i=0, len=history.length; i<len; i++ ) {
                var h = fromServer ? history[i] : JSON.parse(history[i]);
                var id = h[0];
                if( id > _maxid ) {
                    _maxid = id;
                }
                var stamps = h[1];
                var data = h[2];

                var obj = _id2obj[ id ];
                if( obj ) {
                    obj._data = data;
                    _dirty( id, obj, fromServer );
                } else {
                    obj = _newobj(stamps,data,id,true );
                }
                obj._on_load();
            }
        }        
    }
    
    function syncToServer() {
        var toSync;
        toSync = _remoteStoreDirty;
        _remoteStoreDirty = {};
        var syncList = [];
        for( var key in toSync ) {
            var ts = toSync[key];
            if( ts._save_me_p() ) {
                syncList.push( [ ts.id, ts._stamps, ts._save_data() ] );
            }
        }
        var json = JSON.stringify( syncList );
        var url = '/login/yto';

        //TODO - include last update times
        yote_worker.contact( url, 'POST', 'y=' + encodeURIComponent(json), function( data ) {
            if( data ) {
                var json = JSON.parse( data );
                root.set( 'ysyn', json[0] );
            }
        } );
    }
    
    var _synctime, _remoteStoreDirty = {};
    function _dirty( idx, obj, fromRemoteStore ) {
        if( fromRemoteStore !== true ) {
            _remoteStoreDirty[idx] = obj;
        }
        for( var key in _callerDirties ) {
            _callerDirties[ key ][idx] = obj;
        }

        // goofy logic to make it atomic
        clearTimeout( _synctime );
        _synctime = setTimeout( syncToServer, 2000 ); 
    }

    setInterval( syncFromServer, 2000 );

    function _newobj(stamps,startdata,id,isFromStore) {
        var idx = id || ++_maxid;
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
                var val = isFromStore ? startdata[key] : _check( startdata[key] );
                if( val !== undefined ) {
                    newobj._data[key] = val;
                }
            }
        }
        _dirty( idx, newobj );
        return newobj;
    } // _ newobj

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
            };

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

            obj.init = function( history ) { //inits from the client, but it should honor timestamps to get the most recent stuff
                // this is where things would be synced up and passed back
                loadHistory( history, false );
                _dirty( 1, this, true );
                return this;
            };

            
            obj.newlist = function( initial_list ) {
                return that.newobj( '_list', initial_list );
            }; //yote_worker.newlist
            
            obj.newobj = _newobj;
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
//            console.warn( "No stamp function for '" + stampname + "'" );
        }
        return obj;
    } //_stamp


    function _makeBaseObj( id ) { //returns base object
        var obj = {
            id   : id,
            _data : {},
            _stamps : [],
            _on_load : function() { }, //override me
            _save_me_p : function() { return true; }, //override, should this be saved
            _save_data : function() { return this._data; }, //override me
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
                var list = this.get( listname );
                if( list && ! list.splice ) {
//                    console.warn( "Tried to remove from a non existant list" );
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
//                    console.warn( "No listeners for '" + tag + "'" );
                }
            }
        };
        if( id ) {
            _id2obj[ id + '' ] = obj;
        }
        return obj;
    } //_makeBaseObj

    // returns an object, either the cache or server
    function _fetch( id ) {
        var obj = _id2obj[ id + '' ];
        return obj;
    } //_fetch

    // ----------- PUBLIC FUN

    yote_worker.fetch = _fetch;

    yote_worker.fetch_root = function() {
        if( root ) { return root; }
        root = _fetch( 1 ) || _stamp( '_yote_root', _makeBaseObj(1) );
        return root;
    }; //yote_worker.fetch_root

    yote_worker.contact = function( url, proto, data, fun ) {
        var oReq = new XMLHttpRequest();
        oReq.addEventListener("loadend", function() {
            fun( oReq.responseText );
        } );
        oReq.addEventListener("error", function(e) { 
            fun( e );
        } );
        oReq.addEventListener("abort", function(e) { 
            fun( e );
        } );
        
        oReq.open( proto, url, false );
        oReq.setRequestHeader("Content-type", "application/x-www-form-urlencoded");
        if( data ) {
            oReq.send( data );
        } else {
            oReq.send();
        }
    }; //yote_worker.contact

    importScripts( '/js/FOO.js' ); // stamp definitions

    syncFromServer();

    // ensure a root exists
    yote_worker.fetch_root();
    
    importScripts( '/js/BAR.js' ); // after sync, do this stuff, usually checking to see if data is there
    
    
}; //yote_worker.init

yote_worker.init();


//web worker
onconnect = function(e) {
//    console.log( "Worker got req" );

    var port = e.ports[0];

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
            yote_worker.callerDirties[ key ] = dirties;
            call_args = Array.isArray( call_args ) ? call_args : call_args ? [ call_args ] : [];
            var result = obj[ method ].apply( obj, call_args );
            delete yote_worker.callerDirties[ key ];

            var updates = [];
            var methods = {};
            for( var did in dirties ) {
                var upobj = dirties[did];
                updates.push( [ upobj.id, upobj._stamps, upobj._data ] );
                var stamps = upobj._stamps;
                for( var i=0, len = stamps.length; i<len; i++ ) {
                    var stamp = stamps[i];
                    methods[ stamp ] = yote_worker.stamp_methods[ stamp ];
                }
            }
            try {
                var ret = [ key, yote_worker.checklist(result), updates, methods ];
                port.postMessage( ret );
            } catch( err ) { port.postMessage( "ERRR" + err + " " + method + " ) " +  JSON.stringify(result) ); }
        } else {
            // TODO - error response
//            console.warn( "ERROR: ERROR: object method requested not found" );
            port.postMessage( "ERROR: ERROR: object method '" + method + "' requested not found for " + obj );
        }
        }catch(err) { port.postMessage( "ER " + err + " <" + JSON.stringify( e.data ) + "><" +e.data + ">" ); }
    } );
    yote_worker.root = yote_worker.fetch_root();

    port.start();
};
//console.log( "yote_worker load" );
