$.yote.system.util = {

    embed_editor:function( attachpoint, appname, recursion_block ) {
        if( recursion_block == true ) { return; }
        if( ! $.yote.logged_in() ) {
            var backhere = (function(ap,an){
                return function() { 
                    $.yote.system.util.embed_editor(ap,an,true); 
                }
            })( attachpoint, appname );
            $.yote.util.make_login_box({ target:attachpoint,
                                         on_login:backhere,
                                         on_register:backhere,
                                         on_recover:backhere
                                       } );
            return;
        }
        attachpoint.empty();
        var acct = $.yote.get_account();
        
        if( acct.get_is_root() == 0 ) {
            attachpoint.append( "Must be a root account to edit" );
            return;
        } 

        var app = $.yote.get_app( '/' );
        console.dir( app );
        

    }, //embed_editor
};