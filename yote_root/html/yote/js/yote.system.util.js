$.yote.util.system = {

    embed_editor:function( attachpoint, appname_block ) {
        var login = $.yote.get_login();
        
        if( login.get_is_root() == 0 ) {
            attachpoint.append( "Must be a root account to edit" );
            return;
        } 

        var app = $.yote.fetch_app();
        console.dir( app );

    }, //embed_editor

    // use like system_panel( somediv, (function(f,ap,bp,cp){return function() { f(ap,bp,cp); }; )(myfunc,a,b,c) );
    system_panel:function( attachpoint, system_function, require_root ) {
        if( $.yote.is_logged_in() ) {
	    system_function();
	} else {
            $.yote.util.make_login_box({ target:attachpoint,
                                         on_login:system_function,
                                         on_register:system_function,
                                         on_recover:system_function,
                                         require_root:require_root
                                       } );
        }
    }, //system_panel
    
};
