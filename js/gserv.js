/*`
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
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

    create_obj:function(data,appname) {
	var root = this;
	return (function(x) {
	    var o = {
		_app:appname,
		_d:{},
		id:x.id,
		reload:function(){},
		length:function() {
		    var cnt = 0;
		    for( key in this._d ) {
			++cnt;
		    }
		    return cnt;
		}
	    };

	    /*
	      assign methods
	    */
	    if( typeof x.m === 'object' ) {
		for( m in x.m ) {
		    o[x.m[m]] = (function(key) {
			    return function( params, extra ) {
				var failhandler = root.error;
				var passhandler = function(d) {};
				if( typeof extra === 'object' ) {
				    failhandler = typeof extra.failhandler === 'undefined' ? root.error : extra.failhandler;
				    passhandler = typeof extra.passhandler === 'undefined' ? passhandler : extra.passhandler;
				}
				var ret = root.message( {
				    app:o._app,
				    cmd:key,
				    data:params,
				    wait:true,
				    async:false,
				    failhandler:failhandler,
				    passhandler:passhandler
				} ); //sending message
			
				if( typeof ret.r === 'object' ) {
				    return root.create_obj( ret.r, o._app );
				} else {
				    return ret.r;
				}
			    } } )(x.m[m]);
		} //each method
	    } //methods

	    // get fields
	    if( typeof x.d === 'object' ) {
		for( fld in x.d ) {
		    var val = x.d[fld];
		    if( typeof val === 'object' ) {
			o._d[fld] = (function(x) { return root.create_obj(x); })(val);
		    } else {
			o._d[fld] = (function(x) { return x; })(val);
		    }
		}
	    }

	    o.get = function( key ) {
		var val = this._d[key];
		if( typeof val === 'undefined' ) return false;
		if( typeof val === 'object' ) return val;
		if( (0+val) > 0 ) {
		    return root.fetch_obj(val,this._app);
		}
		return val.substring(1);
	    }

	    if( (0 + x.id ) > 0 ) {
		root.objs[x.id] = o;
		o.reload = (function(thid,tapp) {
		    return function() {
			root.objs[thid] = null;
			var replace = root.fetch_obj( thid, tapp );
			this._d = replace._d;
			return this;
		    }
		} )(x.id,appname);
	    }

	    return o;
	})(data);
    }, //create_obj

    fetch_obj:function(id,app) {
	if( typeof this.objs[id] === 'object' ) {
	    return this.objs[id];
	}
	return this.create_obj( this.message( {
	    app:app,
	    cmd:'fetch',
	    data:{ id:id },
	    wait:true,
	    async:false,
	} ).r, app );
    },

    get_app:function( appname ) {
	return this.create_obj( this.message( {
	    app:appname,
	    cmd:'fetch_root',
	    data:{ app:appname },
	    wait:true,
	    async:false,
	} ).r, appname );
    },


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
	    dataFilter:function(a,b) { 
		return a; 
	    },
	    error:function(a,b,c) { root.error(a); },
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

