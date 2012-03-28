/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Here are the following public yote calls :
 *  * reload_all     - reloads all yote objects that are in the yote queue
 *  * create_account - sets the login token
 *  * login          - sets the login token
 *  * get_root       - returns a yote app object (uses login token)
 *  * methods attached to yote object :
 *    ** reload - refreshes the data of this object with a call to the server
 *    ** get(field) - returns a yote object or a scalar value attached to this yote object (uses login token)
 *    ** any method defined on the server side, which returns a yote object or a scalar value (uses login token)
 */
$.yote = {
    token:null,
    err:null,
    objs:{},

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
                _dirty:false,
		        _d:{},
		        id:x.id,
		        class:x.c,
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
				                async:false,
				                app:o._app,
				                cmd:key,
				                data:params,
				                failhandler:failhandler,
                                id:o.id,
				                passhandler:passhandler,
                                verb:'PUT',
				                wait:true,
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

	        o.get = function( key ) {
		        var val = this._stage[key] || this._d[key];
		        if( typeof val === 'undefined' ) return false;
		        if( typeof val === 'object' ) return val;
		        if( (0+val) > 0 ) {
		            return root.fetch_obj(val,this._app);
		        }
		        return val.substring(1);
	        };

	        // get fields
	        if( typeof x.d === 'object' ) {
		        for( fld in x.d ) {
		            var val = x.d[fld];
		            if( typeof val === 'object' ) {
			            o._d[fld] = (function(x) { return root.create_obj(x); })(val);
			            
		            } else {
			            o._d[fld] = (function(x) { return x; })(val);
		            }
		            o['get_'+fld] = (function(fl) { return function() { return this.get(fl) } } )(fld);
		        }
	        }

            // stages functions for updates
            o.stage = function( key, val ) {
                if( this._stage[key] !== root.translate_data( val ) ) {
                    this._stage[key] = root.translate_data( val );
                    this._dirty = true;
                }
            }

            // resets staged info
            o.reset = function() {
                this._stage = {};
            }

            o.is_dirty = function(field) {
                return typeof field === 'undefined' ? this._dirty : this._stage[field] !== this._d[field] ;
            }

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
            o.send_update = function(data,failhandler,passhandler) {
                var to_send = {};
                if( this.c === 'Array' ) {                        
                    to_send = Array();
                }
                if( typeof data === 'undefined' ) {
                    for( var key in this._stage ) {
                        if( this.c === 'Array' ) {
                            to_send.push( root.untranslate_data(this._stage[key]) );
                        } else {
                            to_send[key] = root.untranslate_data(this._stage[key]);
                        }
                    }
                } else {
                    for( var key in data ) {
                        if( this.c === 'Array' ) {
                            to_send.push( data[key] );
                        } else {
                            to_send[key] = data[key];
                        }
                    }
                }
                var needs = 0;
                for( var key in to_send ) { 
                    needs = 1;
                }
                if( needs == 0 ) { return; }
                
                root.message( {
                    app:this._app,
                    async:false,
                    data:to_send,
                    failhandler:function() {
                        if( typeof failhandler === 'function' ) {
                            failhandler();
                        }
                    },        
                    id:this.id,
                    passhandler:(function(td) {
                        return function() {
                            for( var key in td ) {
                                o._d[key] = root.translate_data(td[key]);
                            }
                            o._stage = {};
                            if( typeof passhandler === 'function' ) {
                                passhandler();
                            }
                        }
                    } )(to_send),
                    verb:'POST',
                    wait:true 
                } );
            };

	        if( (0 + x.id ) > 0 ) {
		        root.objs[x.id] = o;
		        o.reload = (function(thid,tapp) {
		            return function() {
                        root.objs[thid] = null;
			            var replace = root.fetch_obj( thid, tapp );
			            this._d = replace._d;
                        for( fld in this._d ) {
                            if( typeof this['get_' + fld] !== 'function' ) {
                                this['get_'+fld] = (function(fl) { return function() { return this.get(fl) } } )(fld);
                            }
                        }
			            root.objs[thid] = this;
			            return this;
		            }
		        } )(x.id,an);
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
            async:false,
            cmd:'multi_fetch',
            data:{ ids:to_fetch },
            passhandler:function(data) {
                for( var key in data.r ) {
                    root.create_obj( data.r[key] );
                }
            },
            verb:'PUT',
            wait:true,
        } );
    }, //multi_fetch_obj

    fetch_obj:function(id,app,passhandler,failhandler ) {
	    if( this.is_in_cache( id ) ) {
	        return this.objs[id];
	    }
	    return this.create_obj( this.message( {
            async:false,
	        app:app,
            failhandler:failhandler,
	        id:id,
            passhandler:passhandler,
            verb:'GET',
	        wait:true,
	    } ).r, app );
    }, //fetch_obj

    get_app:function( appname,passhandler,failhandler ) {
	    return this.create_obj( this.message( {
            async:false,
            failhandler:failhandler,
	        id:appname,
            passhandler:passhandler,
            verb:'GET',
	        wait:true,
	    } ).r, appname );
    },

    logout:function() {
	    this.token = undefined;
	    this.acct = undefined;
        $.cookie('yoken','');
    }, //logout

    get_account:function() {
	    return this.acct;
    },

    is_logged_in:function() {
        if( typeof this.acct === 'object' ) {
            return true;
        }
        else {
            var t = $.cookie('yoken');
            if( typeof t === 'string' ) {
                return this.verify_token( t );
            }
        }
	    return false;
    }, //is_logged_in

    verify_token:function( token ) {
        var root = this;
        var ans = this.message( {
            async:false,
            cmd:'verify_token',
            data:{
                t:token
            },
            failhandler:root.error,
            wait:true,
            passhandler:function(data) {},
            verb:'PUT',
        } );
        if( typeof ans === 'object' && ans.r ) {
            root.token = token;
            root.acct = root.create_obj( ans.r, root );
            return true;
        }
        return false;
    }, //verify_token

    /*   DEFAULT FUNCTIONS */
    login:function( un, pw, passhandler, failhandler ) {
	    var root = this;
	    this.message( {
            async:false,
            cmd:'login', 
            data:{
                h:un,
                p:pw
            },
            failhandler:failhandler,
            passhandler:function(data) {
	            root.token = data.t;
		        root.acct = root.create_obj( data.a, root );
                $.cookie('yoken',root.token, { expires: 7 });
		        if( typeof passhandler === 'function' ) {
		            passhandler(data);
		        }
	        },
            verb:'PUT',
            wait:true, 
        } );
    }, //login

    // generic server type error
    error:function(msg) {
        console.dir( "a server side error has occurred" );
        console.dir( msg );
    },
    
    create_account:function( un, pw, em, passhandler, failhandler ) {
	    var root = this;
        this.message( {
            async:false,
            cmd:'create_account', 
            data:{
                h:un,
                p:pw,
                e:em
            },
            failhandler:failhandler,
            passhandler:function(data) {
	            root.token = data.t;
		        root.acct = root.create_obj( data.a, root );
                $.cookie('yoken',root.token, { expires: 7 });
		        if( typeof passhandler === 'function' ) {
		            passhandler(data);
		        }
	        },
            verb:'PUT',
            wait:true, 
        } );
    }, //create_account

    recover_password:function( em, from_url, to_url, passhandler, failhandler ) {
	    var root = this;
        this.message( {
            async:false,
            cmd:'recover_password', 
            data:{
		        e:em,
		        u:from_url,
                t:to_url
            },
            failhandler:failhandler,
	        passhandler:passhandler,
        } );
    }, //recover_password

    reset_password:function( token, newpassword, passhandler, failhandler ) {
	    var root = this;
        this.message( {
            async:false,
            cmd:'reset_password', 
            data:{
		        t:token,
		        p:newpassword	
            },
            failhandler:failhandler,
	        passhandler:passhandler,
            verb:'PUT',
            wait:true, 
        } );
    }, //reset_password
    
    remove_account:function( un, pw, em, passhandler, failhandler ) {
	    var root = this;
        this.message( {
            async:false,
            cmd:'remove_account', 
            data:{
                h:un,
                p:pw,
                e:em
            },
            failhandler:failhandler,
            passhandler:function(data) {
	            root.token = data.t;
		        if( typeof passhandler === 'function' ) {
		            passhandler(data);
		        }
	        },
            verb:'PUT',
            wait:true, 
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
        if( typeof data === 'undefined' ) {
            return undefined;
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
        $("body").css("cursor", "wait");
    }, //disable
    
    reenable:function() {
        $.each( this.enabled, function(idx,val) { val.disabled = false } );
        $("body").css("cursor", "auto");
    }, //reenable

    /* general functions */
    message:function( params ) {
        var root  = this;
        var data  = root.translate_data( params.data || {} );
        var async = params.async == true ? 1 : 0;
	    var wait  = params.wait  == true ? 1 : 0;
        var url   = params.url;
        var verb  = params.verb;
        var app   = params.app;
        var cmd   = params.cmd;
        var id    = params.id; //id to act on

        if( async == 0 ) {
            root.disable();
        }
        var url = '/_';
        if( typeof app === 'undefined' ) {
            url = url + '/r';
            if( verb == 'GET' ) {
                url = url + '/' + id;
            }
        } else if( 0 + id > 0 ) {
            url = url + '/i/' + app + '/' + id;
        } else {
            url = url + '/o/' + app + '/' + id;
        }
        if( typeof cmd !== 'undefined' ) {
            url = url + '/' + cmd;
        }

        var put_data = {
            a:app,
            data:data,
            t:root.token,
            w:wait
        };
	    var resp;
	    $.ajax( {
	        async:async,
	        data:{
		        m:$.base64.encode(JSON.stringify( put_data ) )
            },
	        dataFilter:function(a,b) {
		        console.dir('incoming '); console.dir( a );
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
                        console.dir( "Invalid failhandler given. It is type " + typeof params.failhandler + ',' + '. call was : ' + $.dump({
		                    a:params.app,
		                    c:params.cmd,
		                    d:data,
                            id:params.id,
		                    t:root.token,
		                    w:wait
		                }) );
                    } //error case. no handler defined 
                } else {
                    console.dir( "Success reported but no response data received" );
                }
	        },
	        type:verb,
	        url:url
	    } );
        if( async == 0 ) {
            root.reenable();
            return resp;
        }
    } //message
}; //$.yote


