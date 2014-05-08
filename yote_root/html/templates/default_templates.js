base_templates = {

    /** LOGIN FUNCTIONS **/
    refresh_all:function(args) {
	$.yote.reinit();
	$.yote.util.refresh_ui();	
    },

    check_login_status:function(args) {
	return $.yote.is_root() ? "<$$ Logged_in $$>" : "<$$ Logged_out $$>";
    },
    forgot:function(args) {
	$( '#login_div' ).empty().append( $.yote.util.fill_template( { template_name : "Recover_Login" } ) );
	$.yote.util.init_ui();
    },
    show_create_account:function(args) {
	$( '#login_div' ).empty().append( $.yote.util.fill_template( { template_name : "Create_Login" } ) );
	$.yote.util.init_ui();	
    },
    init_login:function(args) {
	if( args['controls'] ) {
	    var vars = args['controls'];
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
					  $.yote.util.run_function( 'refresh_all' );
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
	if( args['controls'] ){
	    var vars = args['controls'];
	    var e = '#' + vars[ 'email' ];
	    $.yote.util.button_actions({
		button : '#' + vars[ 'recover' ],
		texts : [ e ],
		action : function() {
		    var app = $.yote.default_app;
		    app.recover_password( $( e ).val(),
					  function(msg) {
					      alert( msg );
					  },
					  function(err) {
					      $(m).empty().append("ERROR : " + err );
					  }
					);
		} } );
	}
    }, //init_recover

    init_create:function(args) {
	if( args['controls'] ){	    
	    var vars = args['controls'];
	    var h = '#' + vars[ 'handle' ];
	    var e = '#' + vars[ 'email' ];
	    var p = '#' + vars[ 'password' ];
	    var m = '#' + vars[ 'messages' ];
	    $.yote.util.button_actions({
		button : '#' + vars[ 'create' ],
		texts  : [ h, e, p ],
		action : function() {
		    var app = $.yote.default_app;
		    app.create_login( {
			h : $( h ).val(),
			e : $( e ).val(),
			p : $( p ).val()
		    },
				      function(msg) {
					  $(m).empty().append( msg  );
				      },
				      function(err) {
					  $(m).empty().append("ERROR : " + err );
				      }
				    );
		} } );
	}
    }, //init_create
    logout:function(args) {
	$.yote.logout();
	$.yote.util.run_function( 'refresh_all' );
    },


    /** PAGE NAVIGATION FUNCTIONS **/

    init_paginator : function( args ) {
	var collection = args[ 'default_var' ];

	var pag_begin_button_id = args[ 'controls' ][ 'paginate_to_beginning_button' ],
	pag_back_button_id =  args[ 'controls' ][ 'paginate_back_button' ],
	pag_forward_button_id =  args[ 'controls' ][ 'paginate_forward_button' ],
	pag_end_button_id =  args[ 'controls' ][ 'paginate_to_end_button' ];

	if( collection.can_rewind() ) {
	    $( '#' + pag_begin_button_id ).attr( 'disabled', false );
	    $( '#' + pag_back_button_id ).attr( 'disabled', false );
	    $( '#' + pag_begin_button_id ).click( function() { collection.first(); $.yote.util.run_function( 'refresh_all' ); } );
	    $( '#' + pag_back_button_id ).click( function() { collection.back(); $.yote.util.run_function( 'refresh_all' ); } );
	} else {
	    $( '#' + pag_begin_button_id ).attr( 'disabled', true );
	    $( '#' + pag_back_button_id ).attr( 'disabled', true );
	}
	if( collection.can_fast_forward() ) {
	    $( '#' + pag_forward_button_id ).attr( 'disabled', false );
	    $( '#' + pag_end_button_id ).attr( 'disabled', false );
	    $( '#' + pag_forward_button_id ).click( function() {
		collection.forwards();
		$.yote.util.run_function( 'refresh_all' );
	    } );
	    $( '#' + pag_end_button_id ).click( function() { collection.last(); $.yote.util.run_function( 'refresh_all' ); } );
	} else {
	    $( '#' + pag_forward_button_id ).attr( 'disabled', true );
	    $( '#' + pag_end_button_id ).attr( 'disabled', true );
	}
    }, //init_paginator

    init_search_hash : function( args ) {
	var collection = args[ 'default_var' ];
	var search_button_id = args[ 'controls' ][ 'search_btn' ],
	search_val_id =  args[ 'controls' ][ 'search_val' ];
	$( '#' + search_val_id ).val( collection.hashkey_search_value );
	$.yote.util.button_actions( {
	    button :  '#' + search_button_id,
	    texts : [ '#' + search_val_id  ],
	    action : function() {
		collection.hashkey_search_value = [ $( '#' + search_val_id ).val() ],
		$.yote.util.run_function( 'refresh_all' );
	    }
	} )
	
    }, //init_search_hash

    init_search_list : function( args ) {
	var collection = args[ 'default_var' ];
	var search_button_id = args[ 'controls' ][ 'search_btn' ],
        search_val_id =  args[ 'controls' ][ 'search_val' ];
	$( '#' + search_val_id ).val( collection.search_values.join(' ') );
	$.yote.util.button_actions( {
	    button :  '#' + search_button_id,
	    texts : [ '#' + search_val_id  ],
	    action : function() {
		collection.search_fields = args[ 'vars' ][ 'search_fields' ].trim().split(/ +/);
		collection.search_values = $( '#' + search_val_id ).val().trim().split(/ +/);
		$.yote.util.run_function( 'refresh_all' );
	    }
	} )

    } //init_search_list
} //base_templates
