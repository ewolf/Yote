/*jslint white: true */
/*jslint nomen: true */
/*jslint plusplus : true */

// the exception is so that things can easily be wrapped inside a onReady sort of thing
yote = { init : function() { throw new Error("yote_local not yet loaded"); } };
yote_local = yote;
yote_local.init = function() {
    var root;

    var _id2obj, _stamps;

    function _check( obj ) {
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

    function _dirty( idx, obj ) {
        localStorage.setItem( "yote_id_" + idx, JSON.stringify( {
            s : obj._stamps,
            d : obj._data
        } ) );
    }

    _stamps = {
        '_list_container' : function( obj ) {
            obj._list_container_stamp_names = {};
            obj.calculate = function(/* arguments */) { };
            obj.remove_entry = function( args ) {
                var listName = args[0], entry = args[1];
                this.remove_from( listName, entry );
                this.calculate( 'removed_entry' );
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
            obj._data = [];

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
            obj.push = function( item ) {
                var ret = obj._data.push( _check( item ) );
                this.fireAllUpdateListeners("push");
                _dirty( this.id, this );
                return ret;
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
            obj.unshift = function( item ) {
                var ret = obj._data.unshift( _check(item) );
                this.fireAllUpdateListeners("unshift");
                _dirty( this.id, this );
                return ret;
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
            obj.newlist = function() {
                return that.newobj( '_list' );
            }; //yote_local.newlist
            
            obj.newobj = function(/* list of stamps, if the first is an array reference, everything in that */) {
                var idx;
                (idx = (1 + (parseInt(localStorage.getItem( "yote_maxid" ))||0)) ) && localStorage.setItem( "yote_maxid", idx );
                var newobj = _makeBaseObj(idx);
                for( var i=0, len=arguments.length; i<len; i++ ) {
                    var sname = arguments[i];
                    if( Array.isArray( sname ) ) {
                        for( var j=0, len2 = sname.length; j<len2; j++ ) {
                            _stamp( sname[j], newobj );
                        }
                    } else {
                        _stamp( sname, newobj );
                    }
                }
                _dirty( idx, newobj );
                return newobj;
            }; //yote_local.newobj
            return obj;
        }
    }; //_stamps

    yote_local.addToStampers = function( name, fun ) {
        _stamps[ name ] = fun;
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
            add_to : function( listname, obj ) {
                var list = this.get( listname );
                if( list && ! list.push ) {
                    throw new Error( "Tried to add to a non-array" );
                }
                if( ! list ) {
                    list = yote_local.newlist();
                    this.set( listname, list );
                }
                return list.push( obj );
            },
            remove_from : function( listname, obj ) {
                var list = this.get( listname ), i;
                if( ! list || ! Array.isArray( list ) ) {
                    console.warn( "Tried to remove from a non existant list" );
                    return;
                }
                for( i=0; i<list.length; i++ ) {
                    if( list[ i ] === obj ) {
                        list.splice( i, 1 );
                    }
                }
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
        if( ! obj ) {
            var json = localStorage.getItem( "yote_id_" + id );
            if( json ) {
                json = JSON.parse( json );
                obj  = _makeBaseObj( id );
                len = json.s.length;
                obj._data = json.d;
                _id2obj[ id ] = obj;
                for( i=0; i<len; i++ ) {
                    _stamp( json.s[i], obj );
                }
                return obj;
            }
        }
        return obj;
    } //_fetch

    // ----------- PUBLIC FUN

    yote_local.stowAll = function() {}

    yote_local.fetch = _fetch;

    yote_local.fetch_root = function() {
        parseInt(localStorage.getItem( "yote_maxid" )) > 0 || localStorage.setItem( "yote_maxid", 1 );

        return _fetch( 1 ) || _stamp( '_yote_root', _makeBaseObj(1) );
    }; //yote_local.fetch_root

    yote_local.init = function() {
        return yote_local.fetch_root();
    };

    // TODO - set up a timer to stow all periodically?

    // TODO - recycle program

    // stamps are added by loading in javascript files

    // init was called, so should have a return value of the root
    root = yote_local.fetch_root();
    return root;

}; //yote.init
