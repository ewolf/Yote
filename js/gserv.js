/*`
 * Here are the following public gserv calls :
 *  * init           - takes the url of the gserv relay cgi and sets it for all gserv calls
 *  * reload_all     - reloads all gserv objects that are in the gserv queue
 *  * create_account - sets the login token
 *  * login          - sets the login token
 *  * fetch_root     - returns a gserv object (uses login token)
 *  * methods attached to gserv object :
 *    ** reload - refreshes the data of this object with a call to the server
 *    ** get(field) - returns a gserv object or a scalar value attached to this gserv object (uses login token)
 *    ** any method defined on the server side, which returns a gserv object or a scalar value (uses login token)
 */

$.gServ = {
    token:null,
    err:null,
    url:null,
    objs:{},

    init:function(url) {
        this.url = url;
        return this;
    },

    reload_all:function() { //reloads all objects
	for( id in this.objs ) {
	    this.objs[id].reload();
	}
    },

    newobj:function() {
	var root = this;
	return {
	    length:function() {
		var cnt = 0;
		for( key in this._data ) {
		    ++cnt;
		}
		return cnt;
	    },
	    _data:{},
	    get:function(key) {			       
		var val = this._data[key]
		if( typeof  val === 'undefined' ) return false;
		if( typeof val === 'object' ) return val;
		if( (0+val) > 0 ) { //object reference
		    var objdata = root.fetch( this._app, val );
		    this._data[key] = objdata;
		    return objdata;
		}
		return val.substring(1);
	    }, //get

            _reset:function(data) {
		var obj = this;
		obj._id = data.id;
		if( obj._id === 0 ) { return; }
		obj._app = data.a;
		obj._class = data.c;
		
		//install methods
		if( typeof data.m === 'object' ) {
		    for( var i=0; i< data.m.length; i++ ) {
			obj[data.m[i]] = (function(key) {
			    return function( params, extra ) {
				var ret;
				var async = false;
				var wait = true;
				var failhandler = root.error;
				var passhandler = function(d) {};
				if( typeof extra === 'object' ) {
				    async = typeof extra.async === 'undefined' ? false : extra.async;
				    wait  = typeof extra.wait  === 'undefined' ? true  : extra.wait;
				    failhandler = typeof extra.failhandler === 'undefined' ? root.error : extra.failhandler;
				    passhandler = typeof extra.passhandler === 'undefined' ? passhandler : extra.passhandler;
				}
				root.message( {
					    app:obj._app,
					    cmd:key,
					    data:params,
					    wait:wait,
					    async:async,
					    failhandler:failhandler,
					    passhandler:function(res) {
					    // todo. this is where the magic is going to happen
					    // the return value is either going to be an object or a scalar
					    // if a scalar, then return as is. if an object, use newobj to return it
					      if( typeof res.r === 'object' ) {
						  ret = root.newobj();
						  ret._reset( res.r );
						  obj[key] = (function(x) {
						      return function() {
							  return x;
						      } } )(ret);
					      } else {
						  ret = res.r;
					      }
					      passhandler( ret );
					    }
				    } ); //sending message
				return ret;
			    } } )(data.m[i]);
		    } //each m
		} //method install

		//install data
		if( typeof data.d === 'object' ) {
		    obj._data = data.d;
		} //if data to install
	    }, //reset

            reload:function() { 
		if( ( this._id + 0 ) > 0 ) { // 0 + forces int context
		    root.objs[this._id] = null;
		    return root.fetch(0,this._id,this);
		} 
	    } //reload
	};
    }, //newobj

    fetch:function(appname,id,obj) {
        var root = this;

	if( (0+id)> 0 ) {
	    if( typeof root.objs[id] === 'object' ) {
		return root.objs[id];
	    } 
	} else if( typeof root.objs[appname] === 'object' ) {
	    return root.objs[appname];
	}

        if( typeof obj === 'undefined' ) {  //obj may be defined for reload calls
    	    obj = root.newobj();
        }

        if( (0 + id ) > 0 ) { // 0 + forces int context
            var cmd = 'fetch';
	    root.objs[id] = obj;
        } else {
            var cmd = 'fetch_root';
	    root.objs[appname] = obj;
        }
        var data = root.message( {
            cmd:cmd,
            data:{
                app:appname,
                id:id
            },
            wait:true,
            async:false,
            failhandler:root.error,
            passhandler:function(ad) {
		var appdata = ad.r;
                obj._reset( appdata );
            }
        } );
        return obj;
    }, //fetch
    
	/*   DEFAULT FUNCTIONS */
    login:function( un, pw, passhandler, failhandler ) {
	var root = this;
	this.message( {
            cmd:'login', 
            data:{
                h:un,
                p:pw
            },
            wait:true, 
            async:false,
            passhandler:function(data) {
	        root.token = data.t;
		if( typeof passhandler === 'function' ) {
			passhandler(data);
		}
	    },
            failhandler:failhandler
        } );
    }, //login

    // generic server type error
    error:function(msg) {
        alert( "a server side error has occurred : " + $.dump(msg) );
    },
    
    create_account:function( un, pw, em, passhandler, failhandler ) {
	var root = this;
        this.message( {
            cmd:'create_account', 
            data:{
                h:un,
                p:pw,
                e:em
            },
            wait:true, 
            async:false,
            passhandler:function(data) {
	        root.token = data.t;
		if( typeof passhandler === 'function' ) {
			passhandler(data);
		}
	    },
            failhandler:failhandler
        } );
    }, //create_account

    
    remove_account:function( un, pw, em, passhandler, failhandler ) {
	var root = this;
        this.message( {
            cmd:'remove_account', 
            data:{
                h:un,
                p:pw,
                e:em
            },
            wait:true, 
            async:false,
            passhandler:function(data) {
	        root.token = data.t;
		if( typeof passhandler === 'function' ) {
			passhandler(data);
		}
	    },
            failhandler:failhandler
        } );
    }, //remove_account



	/* general functions */
    message:function( params ) {
        var root = this;
        async = params.async == true ? 1 : 0;
		wait  = params.wait  == true ? 1 : 0;
        var enabled;
        if( async == 0 ) {
            enabled = $(':enabled');
            $.each( enabled, function(idx,val) { val.disabled = true } );
        }
		var resp;
		$.ajax( {
		    async:async,
		    data:{
			    m:$.base64.encode(JSON.stringify( {
						          a:params.app,
							  c:params.cmd,
							  d:params.data,
							  t:root.token,
							  w:wait
							  } ) ) },
		    error:function(a,b,c) { root.error(a) },
		    success:function( data ) {
			    resp = data;
			    if( typeof data.err === 'undefined' ) {
				if( typeof params.passhandler === 'function' ) {
				    params.passhandler(data);
				}
			    } else if( typeof params.failhandler === 'function' ) {
				params.failhandler(data);
			    } else { alert ("Dunno : " +typeof params.failhandler ) }
			},
		    type:'POST',
		    url:root.url
		} );
        if( async == 0 ) {
            $.each( enabled, function(idx,val) { val.disabled = false } );
            return resp;
        }
    } //message
}; //$.gServ

