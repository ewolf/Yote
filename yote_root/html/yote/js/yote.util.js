$.yote.util = {
    ids:0,
    next_id:function() {
        return 'yidx_'+this.ids++;
    },
    stage_text_field:function(attachpoint,yoteobj,fieldname) {
        var val = yoteobj.get(fieldname);
        var idname = this.next_id();
        attachpoint.append( '<input type="text" id="' + idname + '">' );
        $( '#'+idname ).val( val );
        $( '#'+idname ).keyup( (function (o,k,id,initial) {
            return function(e) {
                var newval = $(id).val();
                o._stage(k,newval);
                if( initial != newval || o._is_dirty(k)) {
                    $(id).css('background-color','lightyellow' );
                } else {
                    $(id).css('background-color','white' );
                }
            }
        } )(yoteobj,fieldname,'#'+idname,val) );
        return $( '#' + idname );
    }, //stage_text_field

    stage_textarea:function(args) {
        var attachpoint = args['attachpoint'];
        var yoteobj   = args['yoteobj'];
        var fieldname = args['fieldname'];
        var cols      = args['cols'];
        var rows      = args['rows'];
        var as_list   = args['as_list'];

        var idname    = this.next_id();
        attachpoint.append( '<textarea cols="'+cols+'" rows="'+rows+'" id="' + idname + '"></textarea>' );
        var val;
        if( as_list == true ) {
            var a = Array();
            for( var i=0; i < yoteobj.length(); ++i ) {
                a.push( yoteobj.get( i ) );
            }
            val = a.join( '\n' );
            $( '#'+idname ).attr( 'value', val );
        } else {
            val = yoteobj.get(fieldname);
            $( '#'+idname ).attr( 'value', val );
        }
        $( '#'+idname ).keyup( (function (o,k,id,initial) {
            return function(e) {
                var newval = $(id).attr('value');

                if( initial != newval || o._is_dirty(k)) {
                    $(id).css('background-color','lightyellow' );
                } else {
                    $(id).css('background-color','white' );
                }

                if( as_list == true ) {
                    newval = newval.split( /\r\n|\r|\n/ );
                    for( var nk in newval ) {
                        o._stage( nk, newval[nk] );
                    }
                }
                else {
                    o._stage(k,newval);
                }
            }
        } )(yoteobj,fieldname,'#'+idname,val) );
        return $( '#' + idname );
    }, //stage_textarea

    /*
      yote_obj/yote_fieldname 
      - object and field to set an example from the list
      list_fieldname - field in the list objects to get the item name for.
    */
    stage_object_select:function(args) {
        var attachpoint    = args['attachpoint'];
        var yote_obj       = args['yote_obj'];
        var yote_fieldname = args['yote_fieldname'];
        var yote_list      = args['yote_list'];
        var list_fieldname = args['list_fieldname'];
        var include_none   = args['include_none'];
        var current        = yote_obj.get( yote_fieldname );

        var current_id = typeof current === 'undefined' ? undefined : current.id;
	var idname = this.next_id();
        attachpoint.append( '<SELECT id="'+idname+'">' + (include_none == true ? '<option value="">None</option>' : '' ) + '</select>' );
        for( var i=0; i<yote_list.length(); ++i ) {
            var obj = yote_list.get( i );
            var val = obj.get( list_fieldname );
            $( '#' + idname ).append( '<option value="' + obj.id + '" ' 
                                      + (obj.id==current_id ? 'selected' :'') + '>' + val + '</option>' );
            $( '#' + idname ).click(
                ( function(o,k,id,initial) {
                    return function() {
                        var newid = $(id).val();
                        o._stage(k,undefined);
                        if( initial != newid || o._is_dirty(k) ) {
                            $(id).css('background-color','lightyellow' );
                        } else {
                            $(id).css('background-color','white' );
                        }
                    }
                } )(yote_obj,yote_fieldname,'#'+idname,current_id)
            );
        }
    }, //stage_object_select

    make_select:function(attachpoint,list,list_fieldname) {
	var idname = this.next_id();
        attachpoint.append( '<select id="'+idname+'"></select>' );
	for( var i in list ) {
	    var item = list[i];
	    $( '#'+idname ).append( '<option value='+item.id+'>'+item.get(list_fieldname)+'</option>' );
	}
	return $( '#' + idname );
    },
    make_table:function(extra) {
	var xtr = extra ? extra : '';
	return {
	    html:'<table ' + xtr + '>',
	    add_header_row : function( arry, extra_row, extra_headers ) {
		var xtr_row = extra_row ? extra_row : '';
		var xtr_headers = extra_headers ? extra_headers : '';
		this.html = this.html + '<tr ' + xtr_row + '>';
		for( var i=0; i<arry.length; i++ ) {
		    this.html = this.html + '<th ' + xtr_headers + '>' + arry[i] + '</th>';
		}
		this.html = this.html + '</tr>';
		return this;
	    },
	    add_row : function( arry, extra_row, extra_headers ) {
		var xtr_row = extra_row ? extra_row : '';
		this.html = this.html + '<tr ' + xtr_row + '>';
		for( var i=0; i<arry.length; i++ ) {
		    if( extra_headers ) {
			this.html = this.html + '<td ' + extra_headers[i] + '>' + arry[i] + '</td>';
		    } else {
			this.html = this.html + '<td>' + arry[i] + '</td>';
		    }
		}
		this.html = this.html + '</tr>';		
		return this;
	    },
	    add_param_row : function( arry ) {
		this.html = this.html + '<tr>';		
		if( arry.length > 0 ) {
		    this.html = this.html + '<th>' + arry[0] + '</th>';
		}
		for( var i=1; i<arry.length; i++ ) {
		    this.html = this.html + '<td>' + arry[i] + '</td>';
		}
		this.html = this.html + '</tr>';		
		return this;
	    },
	    get_html : function() { return this.html + '</table>'; }
	}
    }, //make_table

    
    button_actions:function( args ) {
	var but         = args[ 'button' ];
	var action      = args[ 'action' ] || function(){};
	var on_escape   = args[ 'on_escape' ] || function(){};
	var texts       = args[ 'texts'  ] || [];
	var req_texts   = args[ 'required' ];
	var exempt      = args[ 'cleanup_exempt' ] || {};
	var extra_check = args[ 'extra_check' ] || function() { return true; }

	check_ready = (function(rt,te,ec) { return function() {
	    var t = rt || te;
	    var ecval = ec();
	    for( var i=0; i<t.length; ++i ) {
		if( ! $( t[i] ).val().match( /\S/ ) ) {
	    	    $( but ).attr( 'disabled', 'disabled' );
		    return false;
		}
	    }
	    $( but ).attr( 'disabled', ! ecval );
	    return ecval;
	} } )( req_texts, texts, extra_check ) // check_ready

	for( var i=0; i<texts.length - 1; ++i ) {
	    $( texts[i] ).keyup( function() { check_ready(); return true; } );
	    $( texts[i] ).keypress( (function(box,oe) {
		return function( e ) {
		    if( e.which == 13 ) {
			$( box ).focus();
		    } else if( e.which == 27 ) {
			oe();
		    }		   
		} } )( texts[i+1], on_escape ) );
	}

	act = (function( c_r, a_f, txts ) { return function() {
	    if( c_r() ) {
		a_f();
		for( var i=0; i<txts.length; ++i ) {
		    if( ! exempt[ txts[i] ] ) {
			$( txts[i] ).val( '' );
		    }
		}
	    }
	} } ) ( check_ready, action, texts );

	$( texts[texts.length - 1] ).keyup( function() { check_ready(); return true; } );
	$( texts[texts.length - 1] ).keypress( (function(a,oe) { return function( e ) {
	    if( e.which == 13 ) {
		a();
	    } else if( e.which == 27 ) {
		eo();
	    } } } )(act,on_escape) );

	$( but ).click( act );

	check_ready();

	return check_ready;

    }, // button_actions

    make_button: function( id, value, classes, extra ) {
	var ex = extra || '';
	if( classes ) {
	    return '<button ' + ex + ' type="button" id="' + id + '" class="' + classes + '">' + value + '</button>';
	}
	return '<button ' + ex + ' type="button" id="' + id + '">' + value + '</button>';
    }, //make_button

    make_text: function( id, arg ) {
	var args = arg || {};
	var val = args[ 'value' ] || '';
	var cls = args[ 'classes' ] || '';
	var type = args[ 'use_type' ] || 'text'
	var extra = args[ 'extra' ] || '';
	if( val ) {
	    extra = extra + ' value="' + val.replace( '"', '&quot;' ) + '"';
	}
	if( cls ) {
	    return '<input type="' + type + '" id="' + id + '" ' + extra + ' class="' + cls + '">';
	} else {
	    return '<input type="' + type + '" id="' + id + '" ' + extra + '>';
	}
    }, // make_text

    info_div: function( root, text, classes ) {
	if( ! classes ) {
	    classes = 'alert alert-info';
	}
	$( root ).empty().append( '<div class="' + classes + '">' + text + '</div>' );
    }, // info_div

    container_div: function( rows, arg ) {
	var args = arg || {};
	var container_class = args[ 'class' ] ||  'container';
	var div_id = args[ 'div_id' ] ? ' id="' + args[ 'div_id' ] + '"' : '';
	var row_class = 'row';
	if( container_class == 'container-fluid' ) {
	    row_class = 'row-fluid';
	}
	
	var txt = '<div class="' + container_class + '" ' + div_id + '>';
	for( var i=0; i < rows.length; i++ ) {
	    var row = rows[ i ];
	    if( typeof row === 'object' ) {
		txt += '<div class="' + row_class + '">';
		for( var j=0; j < row.length; j++ ) {
		    var col = row[ j ];
		    var cls = 'span1';
		    if( typeof col === 'object' ) {
			cls = col[ 1 ];
			col = col[ 0 ];
		    }
		    txt += '<div class="' + cls + '">' + col + '</div>';
		}
		txt += '</div>';
	    } else {
		txt += row;
	    }
	}
	txt += '</div>';
	return txt;
    }, //container_div


    modal_main_divs: {},

    prep_modal_div: function( div_id, main_div_id ) {
	if( $.yote.util.modal_main_divs[ main_div_id ] ) 
	    return true;
	$.yote.util.modal_main_divs[ main_div_id] = true;
	$( div_id ).empty().append( '<div class="modal-header">' +
				    ' <button type="button" class="close" id="_yote_close_modal_b" data-dismiss="modal" aria-hidden="true">&times;</button>' +
				    '<h3 id="_yote_login_label"></h3>' +
				    '</div>' +
				    '<div class="modal-body" id="' + main_div_id + '"></div>' )
	    .addClass( 'modal' ).addClass( 'hide' ).addClass( 'fade' )
	    .attr( 'role', 'dialog' ).attr( 'aria-labelledby', "login_label" ).attr( 'aria-hidden', 'true' );
	
    }, //prep_modal_div


    make_login_bar:function( args ) {
	/*
	  This builds a login bar with the simple ( so far ) format of a header bar like :   [ { brand icon/html }           { login menu } ]
	*/

	var cls_f = (function(arg) {
	    return function( cls ) {
		var brand_html             = arg[ 'brand_html' ];
		var app                    = arg[ 'app' ];
		var logged_in_function     = arg[ 'logged_in_function' ] || function( login ) {};
		var not_logged_in_function = arg[ 'not_logged_in_function' ] || function() {};
		var container_id           = arg[ 'container_id' ];
		var modal_div              = args[ 'modal_div' ] || '#modal_div';

		var my_login = $.yote.get_login();
		var my_account = null;
		if( app ) {
		    my_account = app.account();
		}
		
		var avatar_img = '';
		var side_txt = '';
		
		var side_array = [];
		
		if( my_login ) {
		    $( container_id ).empty()
			.append( brand_html + 
//				 '<ul class="nav" role="navigation">' +
				 // other navigation options go here
//				 '</ul>' +
				 '<ul class="nav pull-right" role="navigation">' +
				 '<li class="dropdown">' +
				 '<a id="_yote_login-label" href="#" role="button" class="dropdown-toggle" data-toggle="dropdown">' +
				 'logged in as <b>' + my_login.get_handle() + '</b>' +
				 '<b class="caret"></b>' +
				 '</a>' +
				 '<ul class="dropdown-menu" role="menu" aria-labelledby="login-label">' +
				 '<li><a id="_yote_accountsettings" tabindex="-1" href="#">Account Settings</a></li>' +
				 '<li><a id="_yote_changelogin" tabindex="-1" href="#">Sign In as other user</a></li>' +
				 '<li><a id="_yote_logout" tabindex="-1" href="#">Log Out</a></li>' +
				 '</ul>'+
				 '</li>' );
		    $( '#_yote_accountsettings' ).click(function() { $.yote.util.edit_account( modal_div, app ); });

		    var logout = function() {
			$.yote.logout();
			cls( cls );
		    } //logout

		    $( '#_yote_changelogin' ).click(function() {
			logout();
			$.yote.util.login( modal_div, cls );
		    });
		    $( '#_yote_logout' ).click(logout);
		    
		    logged_in_function( my_login, my_account );
		}
		else {
		    $( container_id ).empty().append( '<div>' + brand_html +
						      '<a id="_yote_login" href="#" role="button" aclass="pull-right" STYLE="margin-right:15px;height:auto;float:right;display:inline">' +
						      'Log In' +
						      '</a></div>' );
		    $( '#_yote_login' ).click(function() {
			$.yote.util.login( modal_div, cls );
		    } );
		    not_logged_in_function();
		}
	    } } )( args ); //cls_f

	// invoke the call initially
	(function(clsf){
	    clsf( clsf );		
	})( cls_f );
	
    }, //make_login_bar
//rgba(47, 139, 34, 0.59)

    forgot_password: function( modal_attach_point, login_function ) {
	$.yote.util.prep_modal_div( modal_attach_point, 'modal_main_div' );
	var input_div_txt = $.yote.util.container_div(
	    [
		[ [ '<div id="_yote_forgot_email_row_div">Email ' + $.yote.util.make_text( 'email_t' ) + '</div>', 'span3' ] ],
		[ [ '<div id="_yote_forgot_msg"></div>', 'span3' ] ],
		[ [ $.yote.util.make_button( '_yote_forgot_b', 'Recover' ), 'span2' ] ]
	    ]
	);
	var  actions_panel_div = $.yote.util.container_div(
	    [
		[ [ $.yote.util.make_button( '_yote_login_b', 'Log In', 'btn btn-link' ), 'span2' ] ],
		[ [ $.yote.util.make_button( '_yote_register_b', 'Create Account', 'btn btn-link' ), 'span2' ] ]
	    ]
	);
	var div_txt = $.yote.util.container_div(
	    [
		[ [ input_div_txt, 'span4' ], [ actions_panel_div, 'span2' ] ]
	    ]
	);
	$( '#modal_main_div' ).empty().append( div_txt );
	$( '#modal_main_div' ).css( 'overflow', 'hidden' ); //disable scrolling within the modal
	
	$( '#_yote_login_label' ).empty().append( 'Recover Account' );
	$( '#_yote_login_b' ).click( (function( attachpoint) { return function() { $.yote.util.login( attachpoint, login_function ); } })( modal_attach_point ) );
	$( '#_yote_register_b' ).click( (function( attachpoint) { return function() { $.yote.util.register_account( attachpoint, login_function ); } })( modal_attach_point ) );
	$( modal_attach_point ).on( 'shown', function() {
	    $( '#_yote_email_t' ).focus();
	} );
	$( modal_attach_point ).modal();
	$( '#_yote_email_t' ).focus();
	$.yote.util.button_actions( { button : '#_yote_forgot_b',
				      texts  : [ '#_yote_email_t' ],
				      action : function() {
					  $.yote.fetch_root().recover_password( { e : $( '#_yote_email_t' ).val(),
										  u : window.location.href,
										  t : location.protocol + '//' +
										  location.hostname +
										  (location.port ? ':'+location.port: '') + "/yote/reset.html"
										},
										function( data ) { //pass
										    $.yote.util.info_div( '#_yote_forgot_msg', data );
										    $( '#_yote_forgot_email_row_div' ).empty();
										    $( '#_yote_forgot_b' ).empty().append( 'Close' );
										    $( '#_yote_forgot_b' ).unbind( 'click' );
										    $( '#_yote_forgot_b' ).click( function() {
											$( modal_attach_point ).modal( 'toggle' );
										    } );
										},
										function( data ) { //fail
										    $.yote.util.info_div( '#_yote_forgot_msg', data );
										}
									      );
				      },
				      on_escape: function() {
					  $( modal_attach_point ).modal( 'toggle' );
				      }
				    } );
	
    }, //forgot_password
    
    register_account:function( modal_attach_point, login_function ) {
	$.yote.util.prep_modal_div( modal_attach_point, 'modal_main_div' );
	var input_div_txt = $.yote.util.container_div(
	    [
		[ 'Handle', $.yote.util.make_text( '_yote_handle_t' ) ],
		[ 'Email', $.yote.util.make_text( '_yote_email_t' ) ],
		[ 'Password', $.yote.util.make_text( '_yote_pw_t', { use_type : 'password' } ) ],
		[ 'Password (again)', [ $.yote.util.make_text( '_yote_pw2_t', { use_type : 'password' } ), 'span3' ], '<span id="_yote_pw2_msg"></span>' ],
		[ [ '<div id="_yote_register_msg"></div>', 'span2' ] ],
		[ [ $.yote.util.make_button( '_yote_register_b', 'Create Account', 'btn btn-primary' ), 'span2' ] ]
	    ] );
	var actions_panel_div = $.yote.util.container_div(
	    [
		[ [ $.yote.util.make_button( '_yote_login_b', 'Log In', 'btn btn-link' ), 'span2' ] ],
		[ [ $.yote.util.make_button( '_yote_forgot_b', 'Forgot Password', 'btn btn-link' ), 'span2' ] ]
	    ]
	);
	var div_txt = $.yote.util.container_div(
	    [
		[ [ input_div_txt, 'span4' ], [ actions_panel_div, 'span2' ] ]
	    ]
	);
	$( '#modal_main_div' ).empty().append( div_txt );
	$( '#modal_main_div' ).css( 'overflow', 'hidden' ); //disable scrolling within the modal
	
	/// for the login below, maybe move the create and forgot buttons to a new column on the right side?
	$( '#_yote_login_label' ).empty().append( 'Create Account' );
	$( '#_yote_login_b' ).click( (function( attachpoint) { return function() { $.yote.util.login( attachpoint, login_function ); } })( modal_attach_point ) );
	$( '#_yote_forgot_b' ).click( (function( attachpoint) { return function() { $.yote.util.forgot_password( attachpoint, login_function ); } })( modal_attach_point ) );
	$( modal_attach_point ).on( 'shown', function() {
	    $( '#_yote_handle_t' ).focus();
	} );
	$( modal_attach_point ).modal();
	$( '#_yote_handle_t' ).focus();
	
	$.yote.util.button_actions( { button : '#_yote_register_b',
				      texts  : [ '#_yote_handle_t', '#_yote_email_t', '#_yote_pw_t', '#_yote_pw2_t' ],
				      action : function() {
					  $.yote.create_login( $( '#_yote_handle_t' ).val(),
							       $( '#_yote_pw_t' ).val(),
							       $( '#_yote_email_t' ).val(),
							       function( data ) { //pass
								   $( modal_attach_point ).modal( 'toggle' );
								   login_function();
							       },
							       function( data ) { //fail
								   $.yote.util.info_div( '#_yote_register_msg', data );
							       }
							     ) },
				      extra_check : function() {
					  var ans = $( '#_yote_pw_t' ).val() == $( '#_yote_pw2_t' ).val();
					  if( ans ) {
					      $( '#_yote_register_msg' ).empty();
					      $( '#_yote_pw2_msg' ).empty();
					  } else {
					      $( '#_yote_pw2_msg' ).empty().append( 'Passwords do not match' );
					  }
					  return ans;
				      },
				      on_escape : function() { $( modal_attach_point ).modal( 'toggle' ); }
				    } );
	
    }, //register_account

    login: function( modal_attach_point, login_function ) {
	$.yote.util.prep_modal_div( modal_attach_point, 'modal_main_div' );
	var input_div_txt = $.yote.util.container_div(
	    [
		[ 'Handle', $.yote.util.make_text( '_yote_login_t' ) ],
		[ 'Password', $.yote.util.make_text( '_yote_pw_t', { use_type : 'password' } ) ],
		[ [ '<div id="_yote_login_msg"></div>', 'span2' ] ],
		[ [ $.yote.util.make_button( '_yote_login_b', 'Log In', 'btn btn-primary' ), 'span2' ] ]
	    ] );
	var actions_panel_div = $.yote.util.container_div(
	    [
		[ [ $.yote.util.make_button( '_yote_register_b', 'Create Account', 'btn btn-link' ), 'span2' ] ],
		[ [ $.yote.util.make_button( '_yote_forgot_b', 'Forgot Password', 'btn btn-link' ), 'span2' ] ]
	    ]
	);
	var div_txt = $.yote.util.container_div(
	    [
		[ [ input_div_txt, 'span4' ], [ actions_panel_div, 'span2' ] ]
	    ]
	);
	$( '#modal_main_div' ).empty().append( div_txt );
	$( '#modal_main_div' ).css( 'overflow', 'hidden' ); //disable scrolling within the modal
	
	// set title of modal
	$( '#_yote_login_label' ).empty().append( 'Log In' );
	
	// when opened, put the focus on the handle input
 	$( modal_attach_point ).on( 'shown', function() {
	    $( '#_yote_login_t' ).focus();
	} );
	
	// turn on the modal, put the focus on the handle input
	$( modal_attach_point ).modal();
	$( '#_yote_login_t' ).focus();
	
	// set up button actions
	$( '#_yote_forgot_b' ).click( (function( attachpoint) { return function() { $.yote.util.forgot_password( attachpoint, login_function ); } })( modal_attach_point ) );
	$( '#_yote_register_b' ).click( (function( attachpoint) { return function() { $.yote.util.register_account( attachpoint, login_function ); } })( modal_attach_point ) );
	$.yote.util.button_actions( { button : '#_yote_login_b',
				      texts  : [ '#_yote_login_t', '#_yote_pw_t' ],
				      action : function() {
					  $.yote.login( $( '#_yote_login_t' ).val(), $( '#_yote_pw_t' ).val(),
							function( data ) { //pass
							    $( modal_attach_point ).modal( 'toggle' );
							    login_function( login_function );
							},
							function( data ) { //fail
							    $.yote.util.info_div( '#_yote_login_msg', data, 'alert alert-warning' );
							}
						      ) }
				    } );
    }, //login
    
    edit_account: function( modal_attach_point, app ) {
	$.yote.util.prep_modal_div( modal_attach_point, 'modal_main_div' );
	// function to use when the file is selected. it both resets the file selector and shows the avatar image
	function file_change_func() {
	    account.upload_avatar( { avatar_file : $.yote.upload( '#_yote__yote_fileup' ),
				     p : $( '#_yote_cur_pw_t ' ).val()
				   },
				   function( data ) { //success
				       $( '#_yote_ch_ava_div' ).empty()
					   .append( '<img src=' + account.get_avatar().Url() + '>' );
				       $( '#_yote_ava_div' ).empty().append( '<img height=70 width=70 src="' + account.get_avatar().Url() + '">' )
				       $.yote.util.info_div( '#_yote_change_msg_div', data, 'alert alert-success well' );
				   },
				   function( data ) { //fail
				       $.yote.util.info_div( '#_yote_change_msg_div', data, 'alert alert-error well' );
				   }
				 );
	    $( '#_yote_ch_file_div' ).empty().append( '<input type="file" id="_yote_fileup" name="file">' );
	    $( '#_yote_fileup' ).change( file_change_func );
	} //edit_account -> file_change_func
	
	// find avatar image if any
	var account, ava_img = 'Upload Avatar';
	if( app ) {
	    account = app.account();
	    console.log( [ 'acct', account, app ] );
	    if( account.get( 'avatar' ) ) {
		ava_img = '<img height=70 width=70 src="' + account.get_avatar().Url() + '">';
	    }
	} else {
	    var login = $.yote.get_login();
	    if( login ) {
		if( login.get( 'avatar' ) ) {
		    ava_img = '<img height=70 width=70 src="' + login.get_avatar().Url() + '">';
		}
	    }
	}
	
	// basic layout of modal container
	div_txt = $.yote.util.container_div(
	    [
		[ 'Current Password', $.yote.util.make_text( '_yote_cur_pw_t', { use_type : 'password' } ) ],
		'<hr>',
		[ 'New Password', $.yote.util.make_text( '_yote_new_pw_t', { use_type : 'password' } ) ],
		[ 'New Password (again)', [ $.yote.util.make_text( '_yote_new_pw2_t', { use_type : 'password' } ), 'span3' ],
		  $.yote.util.make_button( '_yote_update_pw_b', 'Update Password' )  ],
		'<hr>',
		[ 'Email', [ $.yote.util.make_text( '_yote_new_email_t' ), 'span3' ], $.yote.util.make_button( '_yote_update_em_b', 'Update' ) ],
		'<hr>',
		[ '<div id="ch_ava_div">' + ava_img + '</div>',
		  '<div id="ch_file_div"><input type="file" id="_yote_fileup" name="file"></div>' ],
		[ [ '<div id="change_msg_div"></div>', 'span3' ] ]
	    ] );
	$( '#modal_main_div' ).empty().append( div_txt );
	
	// set the title of the modal
	$( '#_yote_login_label' ).empty().append( 'Edit Account' );
	
	// actions
	$( '#_yote_fileup' ).change( file_change_func );
	$.yote.util.button_actions( '#_yote_update_pw_b', [ '#_yote_cur_pw_t', '#_yote_new_pw_t', '#_yote_new_pw2_t' ], function() {
	    $.yote.login_obj.reset_password( { op : $( '#_yote_cur_pw_t' ).val(),
					       p  : $( '#_yote_new_pw_t' ).val(),
					       p2 : $( '#_yote_new_pw2_t' ).val() },
					     function (succmsg) {
						 $.yote.util.info_div( '#_yote_change_msg_div', succmsg, 'alert alert-success well' );
					     },
					     function (failmsg) {
						 $.yote.util.info_div( '#_yote_change_msg_div', failmsg, 'alert alert-error well' );
					     }
					   );
	} ); //update_pw_b
	$.yote.util.button_actions( '#_yote_update_em_b', [ '#_yote_cur_pw_t', '#_yote_new_email_t' ], function() {
	    $.yote.login_obj.reset_email( { pw    : $( '#_yote_cur_pw_t' ).val(),
					    email : $( '#_yote_new_email_t' ).val() },
					  function (succmsg) {
					      $.yote.util.info_div( '#_yote_change_msg_div', succmsg, 'alert alert-success well' );
					  },
					  function (failmsg) {
					      $.yote.util.info_div( '#_yote_change_msg_div', failmsg, 'alert alert-error well' );
					  }
					);
	} ); //update_email_b
	
	// show the modal and focus the default input
	$( modal_attach_point ).on( 'shown', function() {
	    $( '#_yote_cur_pw_t' ).focus();
	    $( '#_yote_close_modal_b' ).attr( 'disabled', false );
	} );
	$( modal_attach_point ).modal();
	$( '#_yote_cur_pw_t' ).focus();
    } //edit_account

}//$.yote.util
