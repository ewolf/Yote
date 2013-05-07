var menu_list = [ [ 'About',      'index.html' ],
		  [ 'Quickstart', 'quickstart.html' ],
		  [ 'Install',    'install.html' ],
		  [ 'Client',       'client_docs.html' ],
		  [ 'Server',       'server_docs.html' ],
		  [ 'Samples',    'samples.html' ],
		  [ 'Wishlist',   'Todo.html' ],
		  [ 'Download',   'Yote-current.tar.gz' ]
		];
var admin_menu_list = [ ['Admin', 'admin.html' ] ];


var menu_attach_point;

function make_menus( attach_point ) {
    var current_page = document.URL.match( /\/([^\/]*?)(\#.*)?$/ )[ 1 ];
    menu_attach_point = attach_point;
    var buf = '';
    for( var i=0; i<menu_list.length; i++ ) {
	if( current_page == menu_list[ i ][ 1 ] ) {
	    buf += '<LI><A class="active" HREF="' + menu_list[ i ][ 1 ] + '">' + menu_list[ i ][ 0 ] + '</A></LI>';
	} else {
	    buf += '<LI><A HREF="' + menu_list[ i ][ 1 ] + '">' + menu_list[ i ][ 0 ] + '</A></LI>';
	}
    }
    if( $.yote.is_logged_in() && 1*$.yote.get_login().is_root() ) {
	for( var i=0; i<admin_menu_list.length; i++ ) {
	    if( current_page == admin_menu_list[ i ][ 1 ] ) {
		buf += '<LI><A class="active" HREF="' + admin_menu_list[ i ][ 1 ] + '">' + admin_menu_list[ i ][ 0 ] + '</A></LI>';
	    } else {
		buf += '<LI><A HREF="' + admin_menu_list[ i ][ 1 ] + '">' + admin_menu_list[ i ][ 0 ] + '</A></LI>';
	    }
	}	
    }
  
    buf += '</UL>';

    $( attach_point ).empty().append( buf );

} //make_menus

function attach_login( args ) {
    var attachpoint         = args[ 'attachpoint' ];
    var message_attachpoint = args[ 'message_attachpoint' ];
    var a_login_f           = args[ 'after_login' ]  || function(){};
    var a_logout_f          = args[ 'after_logout' ];
    if( a_logout_f ) {
	var after_logout_f = function() { make_menus( menu_attach_point ); a_logout_f(); }
    } else {
	after_logout_f = function() { make_menus( menu_attach_point ); }
    }
    if( a_logout_f ) {
	var after_login_f = function() { make_menus( menu_attach_point ); a_login_f(); }
    } else {
	after_login_f = function() { make_menus( menu_attach_point ); }
    }

    function msg( message, cls ) {
	$( message_attachpoint ).empty();
	if( message ) {
	    $( message_attachpoint ).append( '<nobr class="' + cls + '">' + message + '</nobr>' );
	}
	after_logout_f();
    }

    var lc = $.yote.util.login_control( { 
	attachpoint        : attachpoint,
	msg_function       : msg,
	on_logout_function : $.yote.util.needs_login,
	after_login_function  : after_login_f,
	after_logout_function : after_logout_f
    } );
    if( $.yote.is_logged_in() ) {
	lc.on_login();
	after_login_f();
    }
    else {
	lc.needs_login();
	after_logout_f();
    } //not logged in
    
} //attach_login
