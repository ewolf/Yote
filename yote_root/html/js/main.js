function attach_login( args ) {
    var attachpoint         = args[ 'attachpoint' ];
    var message_attachpoint = args[ 'message_attachpoint' ];
    var after_login_f       = args[ 'after_login' ]  || function(){};
    var no_login_f          = args[ 'no_login' ] || function() {};
    var after_logout_f      = args[ 'after_logout' ]  || function(){};
    var access_test_f       = args[ 'access_test' ];
    var logged_in_fail_msg  = args[ 'logged_in_fail_msg' ];
    var theapp              = args[ 'app' ];

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
	after_logout_function : after_logout_f,
	logged_in_fail_msg : logged_in_fail_msg,
	access_test : access_test_f,
	app : theapp
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

function page_counter( page ) {
    var page_counter = $.yote.fetch_app('Yote::Util::Counter');
    page_counter.hash_insert( { name : page, 
				key  : page, 
				val  : (page_counter.hash_fetch( { name : page, key : page } )||0) + 1 } );
} //page_counter
