/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2014 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Version 0.1
 */
$.yote.templates = {
    _ids:0,
    _next_id:function() {
        return '__yidx_'+this._ids++;
    }, //_next_id

    // imports templates from a url and places them into the document.
    import_templates:function( url ) {
	$.ajax( {
	    async:false,
	    cache: false,
	    contentType: "text/html",
	    dataFilter:function(a,b) {
		if( $.yote.debug == true ) {
		    console.log('incoming '); console.log( a );
		}
		return a;
	    },
	    error:function(a,b,c) { $.yote._error(a); },
	    success:function( data ) {
		$( 'html' ).append( data );
	    },
	    type:'GET',
	    url: url
	} );
    }, //import_templates

    _after_render_functions : [],
    _templates : {},
    register_template:function( key, value ) {
	$.yote.templates._templates[ key ] = value;
    }, //register template

    _parse_args: function( arg_txt ) {
        var sing_pos = arg_txt.indexOf( "'" );
        var double_pos = arg_txt.indexOf( '"' );
        if( sing_pos >= 0 || double_pos >= 0 ) {
            if( sing_pos > double_pos && double_pos >= 0 ) {
                var parts = arg_txt.match( /^([^\"]*)\"([^"\\]*(\\.[^"\\]*)*\"(\s\S)/ );
            } else {
                parts = arg_txt.match( /^([^\']*)\'([^'\\]*(\\.[^'\\]*)*\'(\s\S)/ );
            }
            if( parts.length != 4 ) {
                var ret = parts[ 1 ].split( /\s+/ );
                ret.push( parts[ 2 ] );
                ret.push.apply( $.yote.templates._parse_args( parts[ 3 ] ) );
                return ret;
            }
        }
        return arg_txt.split( /\s+/ );
    }, // _parse_args

    // 0 : ???, 1 : $$$, 2 : ??, 3 : @ %, 4: $$, 5 : $, 6 : raw text, 7 : ?
    _parse_template:function( template_txt, template_name, recurse ) {
        // clear out comments
        if( ! recurse ) {
	    while( template_txt.indexOf( '<#' ) > -1 ) {
	        var parts = $.yote.templates._template_parts( template_txt, '#', template_name );
                template_txt =  parts[ 0 ] + parts [ 2 ];
	    }

            // and after render functions can be weeded out early
	    while( template_txt.indexOf( '<?' ) > -1 ) {
	        // functions to be run after rendering is done
	        var parts = $.yote.templates._template_parts( template_txt, '?', template_name );
	        try { 
		    var fun = eval( '[' + parts[1] + ']' )[ 0 ];
		    $.yote.templates._after_render_functions.push( 
		        (function( f ) { return function( ctx ) { 
			    try { 
			        f( ctx );
			    } catch( Err ) {
			        console.log( "Error in after render function '" + ctx.template_path + "' in function '" + f + "' : " + Err);
			    }
		        } } )( fun, context ) );
	        }
	        catch( err ) {
		    console.log( "Error compiling after render function in template '" + template_name + "' : '" + err + "' for funtion '" + parts[ 1 ] + "'" );
	        }
	        template_txt = parts[ 0 ] + parts[ 2 ];
	    } // <?
        }

	if( recurse < 2 && template.indexOf( '<???' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '???', template_name );
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 2 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 1 );
	    try { 
		var f = eval( '[' + parts[1] + ']');
                A.push( [ 0, f ] );
                A.push.apply( A, B );
                return A;
	    }
            
	    catch( err ) {
		console.log( "Error in '" + context.template_path + "' in function '" + parts[1] + "' : " + err);
                A.push.apply( A, B );
	    }
	} // ???

	if( recurse < 3 && template.indexOf( '<$$$' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '$$$', template_name );
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 3 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 2 );
            A.push( [ 1, function( ctx ) { return $.yote.templates._register( parts[ 1 ], ctx )  } ] );
            A.push.apply( A, B );
            return A;
	} // $$$

        if( recurse < 4 && template.indexOf( '<??' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '??', template_name );
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 4 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 3 );
	    try { 
		var f = eval( '[' + parts[1] + ']');
                A.push( [ 3, f ] );
                A.push.apply( A, B );
                return A;
	    }
            
	    catch( err ) {
		console.log( "Error in '" + context.template_path + "' in function '" + parts[1] + "' : " + err);
                A.push.apply( A, B );
	    }
	} // ??
        
	// list rows
        if( recurse < 5 && template.indexOf( '<@' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '@', template_name );
	    var args = parts[1].split( /\s+/ );
            var tmpl = args.shift();
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 5 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 4 );
            A.push( [ 4, function( ctx ) { return $.yote.templates.fill_template_container_rows( tmpl, ctx, args )  } ] );
            A.push.apply( A, B );
            return A;
	} // @

	// hash rows
        if( recurse < 6 && template.indexOf( '<%' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '%', template_name );
	    var args = $.yote.templates._parse_args( parts[1] );
            var tmpl = args.shift();
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 6 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 5 );
            A.push( [ 4, function( ctx ) { return $.yote.templates.fill_template_container_rows( tmpl, ctx, args )  } ] );
            A.push.apply( A, B );
            return A;
	} // %

	// fill template
	if( recurse < 7 && template.indexOf( '<$$' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '$$', template_name );
	    var args = $.yote.templates._parse_args( parts[1] );
            var tmpl = args.shift();
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 7 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 6 );
            A.push( [ 5, function( ctx ) { return $.yote.templates.fill_template( tmpl, ctx, args )  } ] );
            A.push.apply( A, B );
            return A;
	} // $$

	// place variable
	if( recurse < 8 && template.indexOf( '<$' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '$', template_name );
	    var args = $.yote.templates._parse_args( parts[1] );
            var vari = args.shift();
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 8 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 7 );
            A.push( [ 6, function( ctx ) { return $.yote.templates.fill_template_variable( vari, ctx, args )  } ] );
            A.push.apply( A, B );
            return A;
	}

        return [ [ 7, template_text ] ];

    }, //_parse_template


    // register templates defined in html
    init:function() {
	$( '.yote_template_definition' ).each( function() {
	    $.yote.templates.register_template( $( this ).attr( 'template_name' ), $( this ).text() );
	} );
    }, //init

    // rebuild the UI, refreshing all templates
    refresh:function() {
	// fill all the templates defined in the body
	$( '.yote_template' ).each( function() {
	    var el = $( this );
	    var templ_name = el.attr( 'template' );
	    if( ! $.yote.templates._templates[ templ_name ] ) {
		console.log( "Error : template '" + templ_name + "' not found" );
		return;
	    }
	    try { 
		el.empty().append( $.yote.templates.fill_template( templ_name ) );
	    } catch( Err ) {
		console.log( "Error filling template '" + templ_name + '" : ' + Err );
	    }
	} );
	
	//  now that all templates have been rendered, run their after render functions
	for( var i = 0 ; i < $.yote.templates._after_render_functions.length; i++ ) {
	    $.yote.templates._after_render_functions[ i ]();
	}

	// reset so next refresh is clean
	$.yote.templates._after_render_functions = [];
    }, //init

    _context_scratch : {}, // all context objects have a reference to this called scratch, so ctx.scratch

    new_context:function() {
	return {
	    vars : {},
	    controls : {},
	    args : [], // args passed in to the template as it was built
	    scratch : $.yote.templates._context_scratch,
	    get: function( key ) { return typeof this.vars[ key ] === 'undefined' ? ( key == '_app_' ? $.yote.fetch_default_app() : key == '_acct_' ? $.yote.fetch_account() : undefined ) : this.vars[ key ]; },
	    set: function( key, val ) { this.vars[ key ] = val; },
	    clone : function() {
		var clone = {
		    vars     : Object.clone( this.vars ),
		    controls : Object.clone( this.controls ),
		    args     : Object.clone( this.args ),
		    hashkey_or_index  : this.hashkey_or_index,
		}; //TODO : add hash key and index
		clone.clone = this.clone;
		clone.set = this.set;
		clone.get = this.get;
		clone.scratch = $.yote.templates._context_scratch;
		return clone;
	    } //clone
	};
    }, //new_context

    fill_template:function( template_name, old_context, args ) {

	var template = $.yote.templates._templates[ template_name ];
	if( ! template ) { 
	    console.log( "Error : Template '" + template_name + '" not found.' );
	    return ''; 
	}

	// a new context is only made when there is a template id assigned
	var context = old_context ? old_context.clone() : $.yote.templates.new_context();
	context.template_id = $.yote.templates._next_id();
	if( old_context ) {
	    context.template_path = old_context.template_path + '/' + template_name;
	} else {
	    context.template_path = '/' + template_name;
	}
	context.args = args;

	return $.yote.templates._fill_template_text( template, context, template_name );
    }, //fill_template

    _fill_template_text:function( template, context, template_name ) {

	// function buliding template ( highest precidence )
	while( template.indexOf( '<???' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '???', template_name );
	    try { 
		var f = eval( '[' + parts[1] + ']');
		template = parts[ 0 ] + f[0]( context ) + parts[ 2 ];
	    }
	    catch( err ) {
		console.log( "Error in '" + context.template_path + "' in function '" + parts[1] + "' : " + err);
		template = parts[ 0 ] + parts[ 2 ];
	    }
	} // ???

	// variable and control definitions for template
	while( template.indexOf( '<$$$' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '$$$', template_name );
	    template = parts[ 0 ] + 
		$.yote.templates._register( parts[ 1 ], context ) 
		+ parts[ 2 ];
	} // $$$

	// function buliding template
	while( template.indexOf( '<??' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '??', template_name );
	    try { 
		var f = eval( '[' + parts[1] + ']' );
		template = parts[ 0 ] + f[0]( context ) + parts[ 2 ];
	    }
	    catch( err ) {
		console.log( "Error in '" + context.template_path + "' in function '" + parts[1] + "' : " + err);
		template = parts[ 0 ] + parts[ 2 ];
	    }
	} // ??

	// list rows
	while( template.indexOf( '<@' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '@', template_name );
	    template = parts[ 0 ] +
		$.yote.templates.fill_template_container_rows( parts[ 1 ], context, true ) +
		parts[ 2 ];
	} // @

	// hash rows
	while( template.indexOf( '<%' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '%', template_name );
	    template = parts[ 0 ] +
		$.yote.templates.fill_template_container_rows( parts[ 1 ], context, false ) +
		parts[ 2 ];
	} // %

	// fill template
	while( template.indexOf( '<$$' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '$$', template_name );
	    var args = $.yote.templates._parse_args( parts[1] );
	    var template_name = args.shift();
	    template = parts[ 0 ] +
		$.yote.templates.fill_template( template_name, context, args.map( function(it) { return $.yote.templates._parse_val(it,context); } ) ) +
		parts[ 2 ];
	} // $$

	// place variable
	while( template.indexOf( '<$' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '$', template_name );
	    var args = $.yote.templates._parse_args( parts[1] );
	    template = parts[ 0 ] +
		$.yote.templates.fill_template_variable( parts[ 1 ], context ) +
		parts[ 2 ];
	}
	while( template.indexOf( '<#' ) > -1 ) {
	    var parts = $.yote.templates._template_parts( template, '#', template_name );
	    template = parts[ 0 ] + parts [ 2 ];
	}
	while( template.indexOf( '<?' ) > -1 ) {
	    // functions to be run after rendering is done
	    var parts = $.yote.templates._template_parts( template, '?', template_name );
	    try { 
		var fun = eval( '[' + parts[1] + ']' )[ 0 ];
		$.yote.templates._after_render_functions.push( 
		    (function( f, ctx ) { return function() { 
			try { 
			    f( ctx );
			} catch( Err ) {
			    console.log( "Error in after render function '" + ctx.template_path + "' in function '" + f + "' : " + Err);
			}
		    } } )( fun, context ) );
	    }
	    catch( err ) {
		console.log( "Error in '" + context.template_path + "' in function '" + parts[1] + "' : " + err);
	    }
	    template = parts[ 0 ] + parts[ 2 ];
	} // <?

	return template;
    }, //_fill_template_text
    

    // fill
    _template_parts:function( txt, sigil, template_name ) {
	var rev_sigil = sigil.split('').reverse().join('');
	var start = txt.indexOf( '<' + sigil );
	var end   = txt.indexOf( rev_sigil + '>' );
	if( end == -1 ) throw new Error( "Error, mismatched template start and end sigils" );
	var len   = sigil.length + 1;

	// recalculate the start if need be...this chunk should not have two 
	// starts in a row..actally just reverse the string and find the 
	// first rev_sigel...so
	//   '<$$ <$$ foo bar $$>' ---> <$$ rab oof $$> $$>
	//                          end ^           ^ lenstring - indexof rev is start
	// however, the while loop will work as well
	
	while( txt.substring( start + len, end ).indexOf( '<' + sigil ) >= 0 ) {
	    start = txt.substring( start + len, end ).indexOf( '<' + sigil );
	}

	if( end < start ) {
	    console.log( "Template error for '"+template_name+"' : unable to find close of <" + sigil );
	    return;
	}
	return [ txt.substring( 0, start ),
		 txt.substring( start + len, end ).trim(),
		 txt.substring( end+len ) ];
    }, //_template_parts

    _parse_val:function( value, context ) {
	if( value.indexOf( '"' ) == 0 ) {
	    return value.replace( /^"/, '' ).replace( /"$/, '' );
	}
	else if( value.indexOf( "'" ) == 0 ) {
	    return value.replace( /^'/, '' ).replace( /'$/, '' );
	}
	var tlist = value.trim().split(/[\.]/);
	var subj = context;
	for( var i=0; i < tlist.length; i++ ) {
	    var part = tlist[ i ];

	    var is_list = part.indexOf( '@' ) > -1;
	    if( is_list ? part.indexOf( '%' ) == -1 : part.indexOf( '%' ) > -1 ) { // XOR
		// list here 
		var cparts = part.split( /[@%]/ );
		if( cparts.length == 2 && cparts[ 1 ].length > 0 ) {
		    subj = subj.get( cparts[ 0 ] );
		    if( ! subj ) return undefined;
		    return subj.wrap( {
			context : context,
			collection_name :  cparts[ 1 ],
			wrap_key : context.template_path,
			is_hash  : ! is_list
		    } );
		} else {
		    if( is_list )
			return $.yote.wrap_native_container( {
			    context   : context,
			    list      : subj.get( cparts[ 0 ] ),
			    cache_key : value,
			    wrap_key  : context.template_path,
			    is_list   : true,
			} );
		    else
			return $.yote.wrap_native_container( {
			    context   : context,
			    hash      : subj.get( cparts[ 0 ] ),
			    cache_key : value,
			    wrap_key  : context.template_path,
			    is_list   : false,
			} );
		}
	    }
	    else if( part == '_app_' ) {
		subj = $.yote.default_app;
	    }
	    else if( part == '_acct_' ) {
		subj = $.yote.fetch_account();
	    }
	    else {
		subj = subj.get( part );
	    }
	    if( ! subj ) return undefined;
	}
	return subj;
    }, //_parse_val

    _register:function( args_string, context ) { //expects "_name_ (new(_hashkey)?)? <control>"

        // now about we change this around so that the following are legit :
        /*
          <$$$ set varname value $$$>
          <$$$ control ctlname <..html control..> $$$>
        */
	var parts   = args_string.match( /^\s*(\S+)\s+(\S+)\s+(\S[\s\S]*)?/ );
	var cmd     = parts ? parts[ 1 ] : undefined;
	var varname = parts ? parts[ 2 ] : undefined;
	var rest    = parts ? parts[ 3 ] : undefined;
	if( cmd == 'set' ) {
	    if( rest.match( /^function[ \(]/ ) ) {
		var fun = eval( '[' + rest + ']' )[ 0 ];
		try { 
		    context.set( varname, fun( context ) );
		} catch( Err ) {
		    console.log( "Error in after render function '" + ctx.template_path + "' in function '" + f + "' : " + Err);
		}
	    }
	    else {
		context.set( varname, $.yote.templates._parse_val( rest, context ) );
	    }
	}
	else if( cmd == 'control' ) {
	    var ctrl_parts = /\*\<[\s\S]* id\s*=\s*['"]?(\S+)['"]? /.exec( rest );
	    var ctrl_id;
	    if( ctrl_parts ) {
		ctrl_id = ctrl_parts[ 1 ];
	    }
	    else {
		ctrl_id = $.yote.templates._next_id();
		rest = rest.replace( /^\s*(<\s*[^\s\>]+)([ \>])/, '$1 id="' + ctrl_id + '" $2' );
	    }
	    context.controls[ varname ] = '#' + ctrl_id;
	    return rest;
        } //has parts
        return '';

    }, //_register

    fill_template_container_rows:function( args_string, context, is_list ) {
	var parts   = args_string.match( /^\s*(\S+)\s+(\S+)\s+(\S+)([\s\S]*)?/ );
	if( parts && parts.length > 3 ) {
	    var templ = parts[ 1 ];
	    if( is_list )
		var subj  = $.yote.templates._parse_val( parts[ 2 ].indexOf( '@' ) == -1 ? parts[ 2 ] + '@' : parts[2], context );
	    else 
		subj  = $.yote.templates._parse_val( parts[ 2 ].indexOf( '%' ) == -1 ? parts[ 2 ] + '%' : parts[2], context );
	    if( ! subj ) {
		console.log( 'Error : no subject found for <@ @> or <% %> in path "' + context.template_path );
		return '';
	    }
	    subj.page_size_limit = 1*parts[ 3 ] || subj.page_size_limit;
	    
	    var old_key  = context.hashkey_or_index;
	    var old_def = context.get( '_' );
	    var old_parent = context.get( '__' );
	    var ret;
	    if( is_list ) {
		ret = subj.to_list().map(function(it,idx){
		    var args = parts[ 4 ] ? parts[ 4 ].split( /\s+/ ) : [];
		    context.hashkey_or_index = idx;
		    context.set( '_', it );
		    context.set( '__', subj );
		    return $.yote.templates.fill_template( templ, context, args.map( function(it) { return $.yote.templates._parse_val(it,context); } ) );
		} ).join('');
	    }
	    else {
		var hash = subj.to_hash();
		var keys = Object.keys( hash );
		keys.sort(); // TODO : a real sort here
		ret = keys.map(function(key,idx,h){
		    var args = parts[ 4 ] ? parts[ 4 ].split( /\s+/ ) : [];
		    context.hashkey_or_index = key;
		    context.set( '_', hash[ key ] );
		    context.set( '__', subj );
		    return $.yote.templates.fill_template( templ, context, args.map( function(it) { return $.yote.templates._parse_val(it,context); } ) );
		} ).join('');
	    }
	    context.hashkey_or_index = old_key;
	    context.set( '_', old_def );
	    context.set( '__', old_parent );

	    return ret;
	}
	if( is_list )
	    console.log( "<@"+args_string+"@> : wrong arguments " );
	else
	    console.log( "<%"+args_string+"%> : wrong arguments " );
	return '';
    }, //fill_template_container_rows

    fill_template_variable:function( arg_string, context ) {
	var args = arg_string.match( /^\s*(\S+)(\s+(\S+)([\s\S]*))?/ );
	if( args && args.length > 1 ) {
	    var cmd = args[ 1 ].toLowerCase();
	    if( cmd == 'get' ) {
		var res = $.yote.templates._parse_val( args[ 3 ], context );
		return typeof res === 'undefined' ? args[ 4 ] : res;
	    } else if( cmd == 'index' || cmd == 'hashkey' ) {
		return context.hashkey_or_index;
	    }	    
	}
	console.log( '<$ ' + arg_string + ' $> not understand for ' + context.template_path );
	return '';
    }, //fill_template_variable


}//$.yote.templates
