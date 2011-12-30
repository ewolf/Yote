$.gServ = {
    token:null,
    err:null,
    url:null,

    init:function(url) {
        this.url = url;
    },

    get_app:function(appname) {
        var root = this;
        var app = {
            app:appname
        };
        var data = root.message(
            'fetch_root',
            {
                app:appname
            },
            true,
            false
        );
        
        if( typeof data.err === 'undefined' ) {
            for( var i=0; i< data.m.length; i++ ) {
                app[data.m[i]] = (function(key) {
                    return function( params ) {
                        var ret;
                        root.message( key,
                                      params,
                                      1,
                                      1,
                                      function(res) { 
                                          if( res.err ) {
                                              root.error( res.err );
                                          } else {
                                              ret = res.r;
                                          } 
                                      },
                                      app.app );
                        return ret;
                    } } )(data.m[i]);
            } //each m
            for( var i=0; i< data.d.length; i++ ) {
                
            } //each d
        } else {
            this.error(data.err);
        }
        return app;
    },

	/*   DEFAULT FUNCTIONS */
    login:function( un, pw ) {
        var root = this;
        this.message( 'login', 
                      {
                          h:un,
                          p:pw
                      },
                      true, 
                      false,
                      function(data) {
                          if( typeof data.err === 'undefined' ) {
                              root.login_pass(data,un);
                              root.token = data.t;
                          } else {
                              root.login_fail(data);
                          }
                      }
                    );
    },
    error:function(msg) {
        alert( "an error has occurred : " + msg );
    },

    /* default login handlers. Override from individual root */
    login_pass:function(data,un) {
        alert( "Logged in : " + data.msg );
    },
    login_fail: function(data) {
        alert( "NOT logged in : " + data.err );
    },
    
    create_account:function( un, pw, em ) {
		var root = this;
        this.message( 'create_account', 
                      {
                          h:un,
                          p:pw,
                          e:em
                      },
                      true, 
                      false,
                      function(data) {
                          if( typeof data.err === 'undefined' ) {
                              root.create_account_pass(data,un);
                              root.token = data.t;
                          } else {
                              root.create_account_fail(data);
                          }
                      }
                    );
    },

    /* default create account handlers. Override from individual root */
    create_account_pass:function(data,un) {
        alert( "Created account : " + data.msg );
    },
    create_account_fail: function(data) {
        alert( "NOT create account : " + data.err );
    },

	/* general functions */
    message:function( cmd, send_data, wait, async, callback, app ) {
        var root = this;
        async = async == true ? 1 : 0;
	wait  = wait  == true ? 1 : 0;
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
			    a:app,
			    c:cmd,
			    d:send_data,
			    t:root.token,
                    w:wait
			} ) ) },
		    error:function(a,b,c) { alert('connection error ' ) },
		    success:function( data ) {
			resp = data;
			if( typeof callback === 'function' ) {
			    callback(data);
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
};