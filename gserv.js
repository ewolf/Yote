jQuery.gServ = {
    make_app:function(target_app,target_url){

        return {
            app:target_app,
            token:null,
            err:null,
            url:target_url,

            login:function( un, pw ) {
                var app = this;
                this.message( 'login', {
                        h:un,
                        p:pw
                    },
                    1, 
                    false,
                    function(xOptions, textStatus) {
                        if( typeof xOptions.err === 'undefined' ) {
                            alert( 'login success' );
                            $("#lname").innerHTML = un;
                            $("#logged_in").css( 'display', 'block' );
                            $("div#login").css( 'display','none' );
                            app.token = xOptions.t;
                        } else {
                            alert(xOptions.err);
                        }
                    }
                    )
            },
            
            create_account:function( un, pw, em ) {
                this.message( 'create_account', {
                        h:un,
                        p:pw,
                        e:em
                    },
                    1, 
                    false,
                    function(xOptions, textStatus) {
                    }
                    );
            },

            message:function( cmd, data, wait, async, callback ) {
                async = async == null ? true : async;
                var enabled;
                if( async == false ) {
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
                            alert("got error : " + textStatus );
                        },
                        dataFilter:function(json) {
                            return JSON.parse(json);
                        },
                        success:function(xOptions, textStatus) {
                            callback(xOptions, textStatus);
                            if( async == false ) {
                                $.each( enabled, function(idx,val) { val.disabled = false } );
                            }
                        }
                    });
            }
        };
    }
};
