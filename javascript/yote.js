/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Here are the following public yote calls :
 *  * init           - takes the url of the yote relay cgi and sets it for all yote calls
 *  * reload_all     - reloads all yote objects that are in the yote queue
 *  * create_account - sets the login token
 *  * login          - sets the login token
 *  * fetch_root     - returns a yote object (uses login token)
 *  * methods attached to yote object :
 *    ** reload - refreshes the data of this object with a call to the server
 *    ** get(field) - returns a yote object or a scalar value attached to this yote object (uses login token)
 *    ** any method defined on the server side, which returns a yote object or a scalar value (uses login token)
 */
$.yote = {
    token:null,
    err:null,
    url:'/cgi-bin/yote/yote.cgi',
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

    dump_cache:function() {
        this.objs = {};
    },

    is_in_cache:function(id) {
        return typeof this.objs[id] === 'object' && this.objs[id] != null;
    },

    cache_size:function() {
        var i = 0;
        for( v in this.objs ) {
            ++i;
        }
        return i;
    },

    create_obj:function(data,appname) {
	    var root = this;
	    return (function(x,an) {
	        var o = {
		        _app:an,
		        _d:{},
		        id:x.id,
                _stage:{},
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
			            return function( params, passhandler, failhandler ) {
				            var ret = root.message( {
				                app:o._app,
                                id:o.id,
				                cmd:key,
				                data:params,
				                wait:true,
				                async:false,
				                failhandler:failhandler,
				                passhandler:passhandler
				            } ); //sending message

                            //dirty objects that may need a refresh
                            if( typeof ret.d === 'object' ) {
                                for( var i=0; i<ret.d.length; ++i ) {
                                    var oid = ret.d[i];
                                    if( root.is_in_cache(oid) ) {
                                        root.objs[oid].reload();
                                    }
                                }
                            }

				            if( typeof ret.r === 'object' ) {
				                return root.create_obj( ret.r, o._app );
				            } else {
                                if( typeof ret.r === 'undefined' ) {
                                    if( typeof failhandler === 'function' ) {
                                        failhandler('no return value');
                                    }
                                    return undefined;
                                }
                                if( (0+ret.r) > 0 ) {
                                    return root.fetch_obj(ret.r,this._app);
                                }
				                return ret.r.substring(1);
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
	        };

            // stages functions for updates
            o.stage = (function(ob)  {
                return function( key, val ) {
                    ob._stage[key] = root.translate_data( val );
                } 
            })(o);

            // loads direct descendents of this object
            o.load_direct_descendents = function() {
                var ids = Array();
                for( var fld in this._d ) {
                    var id = this._d[fld];
                    if( id + 0 > 0 ) {
                        ids.push(id);
                    }
                }
                root.multi_fetch_obj(ids,this._app);
            };

            // sends data structure as an update, or uses staged values if no data
            o.send_update = (function(ob) {
                return function(data,failhandler,passhandler) {
                    var to_send = {};
                    if( typeof data === 'undefined' ) {
                        for( var key in ob._stage ) {
                            to_send[key] = root.untranslate_data(ob._stage[key]);
                        }
                    } else {
                        for( var key in data ) {
                            to_send[key] = data[key];
                        }
                    }
                    var needs = 0;
                    for( var key in to_send ) { 
                        needs = 1;
                    }
                    if( needs == 0 ) { return; }

                    root.message( {
                        app:ob._app,
                        cmd:'update',
                        data:{ id:ob.id, 
                               d:to_send },
                        wait:true,
                        async:false,
                        failhandler:function() {
                            if( typeof failhandler === 'function' ) {
                                failhandler();
                            }
                        },
                        passhandler:(function(td) {
                            return function() {
                                for( var key in td ) {
                                    ob._d[key] = root.translate_data(td[key]);
                                }
                                ob._stage = {};
                                if( typeof passhandler === 'function' ) {
                                    passhandler();
                                }
                            }
                        } )(to_send)
                    } );
                }
            })(o);

	        if( (0 + x.id ) > 0 ) {
		        root.objs[x.id] = o;
		        o.reload = (function(thid,tapp,ob) {
		            return function() {
                        root.objs[thid] = null;
			            var replace = root.fetch_obj( thid, tapp );
			            ob._d = replace._d;
			            root.objs[thid] = ob;
			            return ob;
		            }
		        } )(x.id,an,o);
	        }
	        return o;
        })(data,appname);
    }, //create_obj

    multi_fetch_obj:function(ids,app) {
        var root = this;
        var to_fetch = Array();
        for( var idx in ids ) {
            if( ! this.is_in_cache( ids[idx] ) ) {
                to_fetch.push( ids[idx] );
            }
        }
        this.message( {
            app:app,
            cmd:'multi_fetch',
            data:{ ids:to_fetch },
            wait:true,
            async:false,
            passhandler:function(data) {
                for( var key in data.r ) {
                    root.create_obj( data.r[key] );
                }
            }
        } );
    }, //multi_fetch_obj

    fetch_obj:function(id,app) {
	    if( this.is_in_cache( id ) ) {
	        return this.objs[id];
	    }
	    return this.create_obj( this.message( {
	        app:app,
	        cmd:'fetch',
	        data:{ id:id },
	        wait:true,
	        async:false
	    } ).r, app );
    },

    get_app:function( appname,passhandler,failhandler ) {
        var res = this.message( {
	        app:appname,
	        cmd:'fetch_root',
	        data:{ app:appname },
	        wait:true,
	        async:false,
            failhandler:failhandler,
            passhandler:passhandler
	    } );
        if( typeof res === 'undefined' || typeof res.r === 'undefined' ) {
            return undefined;
        } 
	    return this.create_obj(  res.r, appname );
    },

    logout:function() {
	    this.token = undefined;
	    this.acct = undefined;
    }, //logout

    get_account:function() {
	    return this.acct;
    },

    is_logged_in:function() {
	    return typeof this.acct === 'object';
    }, //is_logged_in


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
		        root.acct = root.create_obj( data.a, root );
		        if( typeof passhandler === 'function' ) {
			        passhandler(data);
		        }
	        },
            failhandler:failhandler
        } );
    }, //login

    // generic server type error
    error:function(msg) {
        console.dir( "a server side error has occurred : " + msg );
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
		        root.acct = root.create_obj( data.a, root );
		        if( typeof passhandler === 'function' ) {
			        passhandler(data);
		        }
	        },
            failhandler:failhandler
        } );
    }, //create_account

    recover_password:function( em, from_url, to_url, passhandler, failhandler ) {
	    var root = this;
        this.message( {
            cmd:'recover_password', 
            data:{
		        e:em,
		        u:from_url,
                t:to_url
            },
            wait:true, 
            async:false,
	        passhandler:passhandler,
            failhandler:failhandler
        } );
    }, //recover_password

    reset_password:function( token, newpassword, passhandler, failhandler ) {
	    var root = this;
        this.message( {
            cmd:'reset_password', 
            data:{
		        t:token,
		        p:newpassword	
            },
            wait:true, 
            async:false,
	        passhandler:passhandler,
            failhandler:failhandler
        } );
    }, //reset_password
    
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

    translate_data:function(data) {
        if( typeof data === 'object' ) {
            if( data.id + 0 > 0 && typeof data._d !== 'undefined' ) {
                return data.id;
            }
            // this case is for paramers being sent thru message
            // that will not get ids.
            var ret = Object();
            for( var key in data ) {
                ret[key] = this.translate_data( data[key] );
            }
            return ret;
        }
        return 'v' + data;
    }, //translate_data

    untranslate_data:function(data) {
        if( data.substring(0,1) == 'v' ) {
            return data.substring(1);
        }
        if( this.is_in_cache(data) ) {
            return this.objs[data];
        }
        console.dir( "Don't know how to translate " + data);
    }, //untranslate_data

    disable:function() {
        this.enabled = $(':enabled');
        $.each( this.enabled, function(idx,val) { val.disabled = true } );
    }, //disable
    
    reenable:function() {
        $.each( this.enabled, function(idx,val) { val.disabled = false } );
    }, //reenable

	/* general functions */
    message:function( params ) {
        var root = this;
        var data = root.translate_data( params.data );
//        console.dir( "to send " + $.dump({ d:data, c:params.cmd }) );
        async = params.async == true ? 1 : 0;
		wait  = params.wait  == true ? 1 : 0;
        if( async == 0 ) {
            root.disable();
        }
	    var resp;
	    $.ajax( {
	        async:async,
	        data:{
		        m:$.base64.encode(JSON.stringify( {
		            a:params.app,
		            c:params.cmd,
		            d:data,
                    id:params.id,
		            t:root.token,
		            w:wait
		        } ) ) },
	        dataFilter:function(a,b) {
//                console.dir('incoming ' + a );
		        return a; 
	        },
	        error:function(a,b,c) { root.error(a); },
	        success:function( data ) {
                if( typeof data !== 'undefined' ) {
		            resp = data; //for returning synchronous
		            if( typeof data.err === 'undefined' ) {
		                if( typeof params.passhandler === 'function' ) {
			                params.passhandler(data);
		                }
		            } else if( typeof params.failhandler === 'function' ) {
		                params.failhandler(data.err);
		            } else { 
                        console.dir( "Invalid failhandler given. It is type " + typeof params.failhandler + ',' + '. call was : ' + {
		                    a:params.app,
		                    c:params.cmd,
		                    d:data,
                                    id:params.id,
		                    t:root.token,
		                    w:wait
		                } );
                    } //error case. no handler defined 
                } else {
                    console.dir( "Success reported but no response data received" );
                }
	        },
	        type:'POST',
	        url:root.url
	    } );
        if( async == 0 ) {
            root.reenable();
            return resp;
        }
    } //message
}; //$.yote


