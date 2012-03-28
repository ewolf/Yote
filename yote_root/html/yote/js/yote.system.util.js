$.yote.system.util = {

    embed_editor:function( attachpoint, appname, recursion_block ) {
        var acct = $.yote.get_account();
        
        if( acct.get_is_root() == 0 ) {
            attachpoint.append( "Must be a root account to edit" );
            return;
        } 

        var app = $.yote.get_app( '/' );
        console.dir( app );

    }, //embed_editor

    // use like system_panel( somediv, (function(f,ap,bp,cp){return function() { f(ap,bp,cp); }; )(myfunc,a,b,c) );
    system_panel:function( attachpoint, system_function, recursion_block ) {
        if( $.yote.logged_in() ) {
	    system_function();
	} else {
            $.yote.util.make_login_box({ target:attachpoint,
                                         on_login:system_function,
                                         on_register:system_function,
                                         on_recover:system_function
                                       } );
        }
    }, //system_panel

};