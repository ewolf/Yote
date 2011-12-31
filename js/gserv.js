$.gServ = {
    token:null,
    err:null,
    url:null,

    init:function(url) {
        this.url = url;
        return this;
    },

    get_app:function(appname) {
        return this.fetch(appname);
    },

    fetch:function(appname,id,app) {
        var root = this;

        if( typeof app === 'undefined' ) {
            app = {};
        }
        if( id > 0 ) {
            var cmd = 'fetch';
        } else {
            var cmd = 'fetch_root';
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
            passhandler:function(appdata) {
                app.id  = appdata.id;
                app.app = appdata.a;
                app.reload = function() { return root.fetch(0,this.id,this) };
                for( var i=0; i< appdata.m.length; i++ ) {
                    app[appdata.m[i]] = (function(key) {
                        return function( params, extra ) {
                            var ret;
                            var async = false;
                            var wait = true;
                            var failhandler = root.error;
                            if( typeof extra === 'object' ) {
                                async = extra.async;
                                wait  = extra.wait;
                                failhandler = extra.failhandler;
                            }
                            root.message( {
                                app:app.app,
                                cmd:key,
                                data:params,
                                wait:wait,
                                async:async,
                                failhandler:failhandler,
                                passhandler:function(res) {
                                    ret = res.r;
                                }
                            } );
                            return ret;
                        } } )(appdata.m[i]);
                } //each m
                for( field in appdata.d ) {
                    if( appdata.d[field] > 0 ) {
                        app['get_'+field] = (function(id,fld) { 
                            return function() {
                                var obj = root.fetch(0,id);
                                this['get_'+fld] = (function(x) { return function() { return x; } } )(obj);
                                return obj;
                            } 
                        })(appdata.d[field],field);
                    } else {
                        app['get_'+field] = (function(val) { 
                            return function() { 
                                 return val; 
                            } 
                        })(appdata.d[field].substring(1));
                    }
                    
                } //each d
            }
        } );
        return app;
    }, //fetch
    
	/*   DEFAULT FUNCTIONS */
    login:function( un, pw, passhandler, failhandler ) {
        this.message( {
            cmd:'login', 
            data:{
                h:un,
                p:pw
            },
            wait:true, 
            async:false,
            passhandler:passhandler,
            failhandler:failhandler
        } );
    }, //login

    // generic server type error
    error:function(msg) {
        alert( "an server side error has occurred : " + msg );
    },
    
    create_account:function( un, pw, em, passhandler, failhandler ) {
        this.message( {
            cmd:'create_account', 
            data:{
                h:un,
                p:pw,
                e:em
            },
            wait:true, 
            async:false,
            passhandler:passhandler,
            failhandler:failhandler
        } );
    }, //create_account

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
                }
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