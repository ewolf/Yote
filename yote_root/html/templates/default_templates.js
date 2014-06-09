base_templates = {

    /** PAGE NAVIGATION FUNCTIONS **/

    init_paginator : function( args ) {
	var collection = args.default_var;

	if( ! collection.can_rewind ) { //test if it has that function
	    console.log( 'warning : init_paginator called for something not a list or hash' );
	    return;
	}

	var pag_begin_button_id    = args.controls.paginate_to_beginning_button,
             pag_back_button_id    =  args.controls.paginate_back_button,
	     pag_forward_button_id =  args.controls.paginate_forward_button,
             pag_end_button_id     =  args.controls.paginate_to_end_button;

	if( collection.can_rewind() ) {
	    $( pag_begin_button_id ).attr( 'disabled', false );
	    $(  pag_back_button_id ).attr( 'disabled', false );
	    $(  pag_begin_button_id ).click( function() { collection.first(); 	
							  $.yote.reinit();
							  $.yote.util.refresh_ui(); } );
	    $(  pag_back_button_id ).click( function() { collection.back(); 
							 $.yote.reinit();
							 $.yote.util.refresh_ui(); } );
	} else {
	    $(  pag_begin_button_id ).attr( 'disabled', true );
	    $(  pag_back_button_id ).attr( 'disabled', true );
	}
	if( collection.can_fast_forward() ) {
	    $(  pag_forward_button_id ).attr( 'disabled', false );
	    $(  pag_end_button_id ).attr( 'disabled', false );
	    $(  pag_forward_button_id ).click( function() {
		collection.forwards();
		$.yote.reinit();
		$.yote.util.refresh_ui();
	    } );
	    $(  pag_end_button_id ).click( function() { collection.last(); 
							$.yote.reinit();
							$.yote.util.refresh_ui(); } );
	} else {
	    $(  pag_forward_button_id ).attr( 'disabled', true );
	    $(  pag_end_button_id ).attr( 'disabled', true );
	}
    }, //init_paginator

    init_search_hash : function( args ) {
	var collection = args[ 'default_var' ];
	var search_button_id = args[ 'controls' ][ 'search_btn' ],
	search_val_id =  args[ 'controls' ][ 'search_val' ];
	$(  search_val_id ).val( collection.hashkey_search_value );
	$.yote.util.button_actions( {
	    button :   search_button_id,
	    texts : [  search_val_id  ],
	    action : function() {
		collection.hashkey_search_value = [ $(  search_val_id ).val() ],
		$.yote.reinit();
		$.yote.util.refresh_ui();
	    }
	} )

    }, //init_search_hash

    init_search_list : function( args ) {
	var collection = args[ 'default_var' ];
	var search_button_id = args[ 'controls' ][ 'search_btn' ],
        search_val_id =  args[ 'controls' ][ 'search_val' ];
	$(  search_val_id ).val( collection.search_values.join(' ') );
	$.yote.util.button_actions( {
	    button : search_button_id,
	    texts  : [ search_val_id  ],
	    action : function() {
		collection.search_fields = args[ 'vars' ][ 'search_fields' ].trim().split(/ +/);
		collection.search_values = $( search_val_id ).val().trim().split(/ +/);
		$.yote.reinit();
		$.yote.util.refresh_ui();
	    }
	} )

    } //init_search_list
} //base_templates
