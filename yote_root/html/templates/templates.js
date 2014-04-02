base_templates = {

    /** LOGIN FUNCTIONS **/

    check_login_status:function(args) {
	return $.yote.is_root() ? "<$$ Logged_in $$>" : "<$$ Logged_out $$>";
    },
    forgot:function(args) {
	$( '#login_div' ).empty().append( $.yote.util.fill_template( { template_name : "Recover_Login" } ) );
	$.yote.util.init_ui();
    },

    init_login:function(args) {
	if( args['vars'] ) {
	    var vars = args['vars'];
	    var h = '#' + vars[ 'handle' ],
	    p = '#' + vars[ 'password' ],
            m = '#' + vars[ 'messages' ];

	    $.yote.util.button_actions({
		button : '#' + vars[ 'login_button' ],
		texts : [ h, p ],
		action : function() {
		    $.yote.login( $(h).val(),
				  $(p).val(),
				  function(msg) {
				      if( $.yote.is_root() ) {
					  refresh_all();
 				      }
				      else if( $.yote.is_logged_in() ) {
					  $(m).empty().append( "ERROR : this account does not have root privileges" );
				      }
				  },
				  function(err) {
				      $(m).empty().append("ERROR : " + err );
				  }
				);
		} } );
	}
    }, //init_login
    init_recover:function(args) {
	if( args['vars'] ){
	    var e = '#' + args[ 'vars' ][ 'email' ];
	    $.yote.util.button_actions({
		button : '#' + vars[ 'recover' ],
		texts : [ e ],
		action : function() {
		    root.recover_password( $(e).val(),
					   function(msg) {
					       $(m).empty().append("ERROR : " + msg );
					   },
					   function(err) {
					       $(m).empty().append("ERROR : " + err );
					   }
					 );
		} } );
	}
    },
    logout:function(args) {
	$.yote.logout();
	refresh_all();
    },


    /** PAGE NAVIGATION FUNCTIONS **/

    init_paginator : function( args ) {
	var collection = args[ 'default_var' ];
	var pag_begin_button_id = args[ 'vars' ][ 'paginate_to_beginning_button' ],
	pag_back_button_id =  args[ 'vars' ][ 'paginate_back_button' ],
	pag_forward_button_id =  args[ 'vars' ][ 'paginate_forward_button' ],
	pag_end_button_id =  args[ 'vars' ][ 'paginate_to_end_button' ];

	if( collection.can_rewind() ) {
	    $( '#' + pag_begin_button_id ).attr( 'disabled', false );
	    $( '#' + pag_back_button_id ).attr( 'disabled', false );
	    $( '#' + pag_begin_button_id ).click( function() { collection.first(); refresh_all(); } );
	    $( '#' + pag_back_button_id ).click( function() { collection.back(); refresh_all(); } );
	} else {
	    $( '#' + pag_begin_button_id ).attr( 'disabled', true );
	    $( '#' + pag_back_button_id ).attr( 'disabled', true );
	}
	if( collection.can_fast_forward() ) {
	    $( '#' + pag_forward_button_id ).attr( 'disabled', false );
	    $( '#' + pag_end_button_id ).attr( 'disabled', false );
	    $( '#' + pag_forward_button_id ).click( function() {
		collection.forwards();
		refresh_all();
	    } );
	    $( '#' + pag_end_button_id ).click( function() { collection.last(); refresh_all(); } );
	} else {
	    $( '#' + pag_forward_button_id ).attr( 'disabled', true );
	    $( '#' + pag_end_button_id ).attr( 'disabled', true );
	}
    }, //init_paginator

    init_search_hash : function( args ) {
	var collection = args[ 'default_var' ];
	var search_button_id = args[ 'vars' ][ 'search_btn' ],
	search_val_id =  args[ 'vars' ][ 'search_val' ];
	$( '#' + search_val_id ).val( collection.hashkey_search_value );
	$.yote.util.button_actions( {
	    button :  '#' + search_button_id,
	    texts : [ '#' + search_val_id  ],
	    action : function() {
		collection.hashkey_search_value = [ $( '#' + search_val_id ).val() ],
		refresh_all();
	    }
	} )
	
    }, //init_search_hash

    init_search_list : function( args ) {
	var collection = args[ 'default_var' ];
	var search_button_id = args[ 'vars' ][ 'search_btn' ],
        search_val_id =  args[ 'vars' ][ 'search_val' ];
	$( '#' + search_val_id ).val( collection.search_values.join(' ') );
	$.yote.util.button_actions( {
	    button :  '#' + search_button_id,
	    texts : [ '#' + search_val_id  ],
	    action : function() {
		collection.search_fields = args[ 'extra' ].split(/ +/);
		collection.search_values = $( '#' + search_val_id ).val().split(/ +/);
		refresh_all();
	    }
	} )

    } //init_search_list
} //base_templates
