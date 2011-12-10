jQuery.gServ = {
    make_app:function(target_app,target_url){
        return {
            app:target_app,
            token:null,
            err:null,
            url:target_url,


	    /*   DEFAULT FUNCTIONS */
            login:function( un, pw ) {
                var app = this;
                this.message( 'login', {
                        h:un,
                        p:pw
                    },
                    true, 
                    false,
                    function(data) {
                        if( typeof data.err === 'undefined' ) {
                            app.login_pass(data,un);
                            app.token = data.t;
                        } else {
                            app.login_fail(data);
                        }
                    }
                    )
            },
            error:function(msg) {
                alert( "an error has occurred : " + msg );
            },

            /* default login handlers. Override from individual app */
            login_pass:function(data,un) {
                alert( "Logged in : " + data.msg );
            },
            login_fail: function(data) {
                alert( "NOT logged in : " + data.err );
            },
            
            create_account:function( un, pw, em ) {
		var app = this;
                this.message( 'create_account', {
                        h:un,
                        p:pw,
                        e:em
                    },
                    true, 
                    false,
                    function(data) {
                        if( typeof data.err === 'undefined' ) {
                            app.create_account_pass(data,un);
                            app.token = data.t;
                        } else {
                            app.create_account_fail(data);
                        }
                    }
                    );
            },

            /* default create account handlers. Override from individual app */
            create_account_pass:function(data,un) {
                alert( "Created account : " + data.msg );
            },
            create_account_fail: function(data) {
                alert( "NOT create account : " + data.err );
            },


	    /* register commands */
	    register_command:function( options ) {
		var app = this;
		if( typeof options === "object" && 
		    options.command != undefined &&
		    options.succeed != undefined &&
		    options.fail    != undefined 
		  ) {
		    var wait = options.wait != undefined ? options.wait : true;
		    var async = options.async != undefined ? options.async : false;
		    
		    app[options.command] = function( data ) {
			app.message( options.command, data, wait, async, function(ret) {
			    if( typeof ret.err === 'undefined' ) {
				options.succeed( ret );
			    } else {
				options.fail( ret );
			    }
			} );
		    };
		} else {
		    $.error( "register_command called with incorrect options" );
		}
	    },

	    /* general functions */
            message:function( cmd, data, wait, async, callback ) {

                var app = this;
                async = async == true ? 1 : 0;
		wait = wait == true ? 1 : 0;
                var enabled;
                if( async == 0 ) {
                    enabled = $(':enabled');
                    $.each( enabled, function(idx,val) { val.disabled = true } );
                }

                $.jsonp({
                        url:this.url,
                        callbackParameter:'callback',
                        data:{ m:$.base64.encode(JSON.stringify( {
                                        a:this.app,
                                        c:cmd,
                                        d:data,
                                        t:this.token,
                                        w:wait
                                    } ) )
                        }, 
                        error:function(xOptions, textStatus) {
                            app.error();
                            if( async == 0 ) {
                                $.each( enabled, function(idx,val) { val.disabled = false } );
                            }
                        },
                        dataFilter:function(json) {
                            return JSON.parse(json);
                        },
                        success:function(xOptions, textStatus) {
                            callback(xOptions);
                            if( async == 0 ) {
                                $.each( enabled, function(idx,val) { val.disabled = false } );
                            }
                        }
                    });
            }
        };
    }
};
