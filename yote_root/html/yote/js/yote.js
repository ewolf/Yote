/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2012 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Here are the following public yote calls :
 */
$.yote = {
    token:null,
    err:null,
    objs:{},

    fetch_root:function() {

        this.root = this._create_obj( this.message( {
            async:false,
            cmd:'fetch_root',
            verb:'PUT',
	        wait:true,
	    } ).r, 1 );

        var t = $.cookie('yoken');
        if( typeof t === 'string' ) {
            var ret = this.root.token_login( { t:t } );
	        if( typeof ret !== 'undefined' ) {
		        this.token     = ret.t;
		        this.login_obj = ret.l;
	        }
        }

	    return this.root;

    }, //fetch_root
    

    _dump_cache:function() {
        this.objs = {};
    },

    _is_in_cache:function(id) {
        return typeof this.objs[id] === 'object' && this.objs[id] != null;
    },

    _cache_size:function() {
        var i = 0;
        for( v in this.objs ) {
            ++i;
        }
        return i;
    },

    _create_obj:function(data,app_id) {
	    var root = this;
	    return (function(x,an) {
	        var o = {
		        _app_id:app_id,
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
				                app_id:o._app_id,
				                cmd:key,
				                data:params,
				                failhandler:failhandler,
                                obj_id:o.id,
				                passhandler:passhandler,
				                wait:true,
				                t:root.token,
			                } ); //sending message

			                if( o.id == 1 && ( key == 'login' || key == 'create_login' ) ) {
				                if( typeof ret.err !== 'string' ) {
				                    root.token = ret.r.d.t.substring(1);
				                }
			                }
			                

                            //dirty objects that may need a refresh
                            if( typeof ret.d === 'object' ) {
                                for( var i=0; i<ret.d.length; ++i ) {
                                    var oid = ret.d[i];
                                    if( root._is_in_cache(oid) ) {
                                        root.objs[oid].reload();
                                    }
                                }
                            }

			                if( typeof ret.r === 'object' ) {
				                return root._create_obj( ret.r, o._app_id );
			                } else {
                                if( typeof ret.r === 'undefined' ) {
                                    if( typeof failhandler === 'function' ) {
                                        failhandler('no return value');
                                    }
                                    return undefined;
                                }
                                if( (0+ret.r) > 0 ) {
                                    return root.fetch_obj(ret.r,this._app_id);
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
		            var obj = root.objs[val] || root.root.fetch(val);
                    if( this._stage[key] == val ) {
                        this._stage[key] = obj;
                    } else {
                        this._d[key] = obj;
                    }
                    return obj;
		        }
		        return val.substring(1);
	        };

	        // get fields
	        if( typeof x.d === 'object' ) {
		        for( fld in x.d ) {
		            var val = x.d[fld];
		            if( typeof val === 'object' ) {
			            o._d[fld] = (function(x) { return root._create_obj(x); })(val);
			            
		            } else {
			            o._d[fld] = (function(x) { return x; })(val);
		            }
		            o['get_'+fld] = (function(fl) { return function() { return this.get(fl) } } )(fld);
		        }
	        }

            // stages functions for updates
            o.stage = function( key, val ) {
                if( this._stage[key] !== root._translate_data( val ) ) {
                    this._stage[key] = root._translate_data( val );
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

            // sends data structure as an update, or uses staged values if no data
            o.send_update = function(data,failhandler,passhandler) {
                var to_send = {};
                if( this.c === 'Array' ) {                        
                    to_send = Array();
                }
                if( typeof data === 'undefined' ) {
                    for( var key in this._stage ) {
                        if( key.match(/^[A-Z]/) ) {
                            if( this.c === 'Array' ) {
                                to_send.push( root._untranslate_data(this._stage[key]) );
                            } else {
                                to_send[key] = root._untranslate_data(this._stage[key]);
                            }
                        }
                    }
                } else {
                    for( var key in data ) {
                        if( key.match(/^[A-Z]/) ) {
                            if( this.c === 'Array' ) {
                                to_send.push( data[key] );
                            } else {
                                to_send[key] = data[key];
                            }
                        }
                    }
                }
                var needs = 0;
                for( var key in to_send ) { 
                    needs = 1;
                }
                if( needs == 0 ) { return; }
                
                root.message( {
                    app_id:this._app_id,
                    async:false,
                    data:to_send,
                    cmd:'update',
                    failhandler:function() {
                        if( typeof failhandler === 'function' ) {
                            failhandler();
                        }
                    },        
                    obj_id:this.id,
                    passhandler:(function(td) {
                        return function() {
                            for( var key in td ) {
                                o._d[key] = root._translate_data(td[key]);
                            }
                            o._stage = {};
                            if( typeof passhandler === 'function' ) {
                                passhandler();
                            }
                        }
                    } )(to_send),
                    wait:true 
                } );
            };

	        if( (0 + x.id ) > 0 ) {
		        root.objs[x.id] = o;
		        o.reload = (function(thid,tapp) {
		            return function() {
			            root.objs[thid] = null;
			            var replace = root.root.fetch( thid );
			            this._d = replace._d;
                        for( fld in this._d ) {
                            if( typeof this['get_' + fld] !== 'function' ) {
                                this['get_'+fld] = (function(fl) { 
                                    return function() { return this.get(fl) } } )(fld);
                            }
                        }
			            root.objs[thid] = this;
			            return this;
		            }
		        } )(x.id,an);
	        }
	        return o;
        })(data,app_id);
    }, //_create_obj

    // generic server type error
    _error:function(msg) {
        console.dir( "a server side error has occurred" );
        console.dir( msg );
    },
    
    _translate_data:function(data) {
        if( typeof data === 'object' ) {
            if( data.id + 0 > 0 && typeof data._d !== 'undefined' ) {
                return data.id;
            }
            // this case is for paramers being sent thru message
            // that will not get ids.
            var ret = Object();
            for( var key in data ) {
                ret[key] = this._translate_data( data[key] );
            }
            return ret;
        }
        if( typeof data === 'undefined' ) {
            return undefined;
        }
        return 'v' + data;
    }, //_translate_data

    _untranslate_data:function(data) {
        if( data.substring(0,1) == 'v' ) {
            return data.substring(1);
        }
        if( this._is_in_cache(data) ) {
            return this.objs[data];
        }
        console.dir( "Don't know how to translate " + data);
    }, //_untranslate_data

    _disable:function() {
        this.enabled = $(':enabled');
        $.each( this.enabled, function(idx,val) { val.disabled = true } );
        $("body").css("cursor", "wait");
    }, //_disable
    
    _reenable:function() {
        $.each( this.enabled, function(idx,val) { val.disabled = false } );
        $("body").css("cursor", "auto");
    }, //_reenable

    /* general functions */
    message:function( params ) {
        var root   = this;
        var data   = root._translate_data( params.data || {} );
        var async  = params.async == true ? 1 : 0;
	    var wait   = params.wait  == true ? 1 : 0;
        var url    = params.url;
        var app_id = params.app;
        var cmd    = params.cmd;
        var obj_id = params.obj_id; //id to act on
        if( async == 0 ) {
            root._disable();
        }
        app_id = app_id || '';
        obj_id = obj_id || '';
        var url = '/_/' + app_id + '/' + obj_id + '/' + cmd;

        var put_data = {
            d:$.base64.encode(JSON.stringify( {d:data} ) ),
            t:root.token,
            w:wait
        };
	    var resp;

        //console.dir('outgoing ' + url );  console.dir( put_data );

	    $.ajax( {
	        async:async,
	        data:put_data,
	        dataFilter:function(a,b) {
		        //console.dir('incoming '); console.dir( a );
		        return a; 
	        },
	        error:function(a,b,c) { root._error(a); },
	        success:function( data ) {
                if( typeof data !== 'undefined' ) {
		            resp = data; //for returning synchronous
		            if( typeof data.err === 'undefined' ) {
		                if( typeof params.passhandler === 'function' ) {
			                params.passhandler(data);
		                }
		            } else if( typeof params.failhandler === 'function' ) {
		                params.failhandler(data.err);
                    } //error case. no handler defined 
                } else {
                    console.dir( "Success reported but no response data received" );
                }
	        },
	        type:'POST',
	        url:url
	    } );
        if( async == 0 ) {
            root._reenable();
            return resp;
        }
    } //message
}; //$.yote


