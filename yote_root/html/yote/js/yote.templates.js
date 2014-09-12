/*
 * LICENSE AND COPYRIGHT
 *
 * Copyright (C) 2014 Eric Wolf
 * This module is free software; it can be used under the terms of the artistic license
 *
 * Version 0.103
 */
if( ! $.yote ) { 
    $.yote = {
        fetch_default_app: function() { return undefined; },
        fetch_account: function() { return undefined; },
        _subj_has_get_p:function() { return false; },
    }; 
}
$.yote.templates = {


    _after_render_functions : [],
    _compiled_templates : {},
    
    _ids : 0,
    _next_id:function() {
        return '__ytidx_'+this._ids++;
    }, //_next_id

    // imports templates from a url and places them into the document.
    import_templates:function( url ) {
	    $.ajax( {
	        async:false,
	        cache: false,
	        contentType: "text/html",
	        dataFilter:function(a,b) {
		        return a;
	        },
	        error:function(a,b,c) { console.log(a); },
	        success:function( data ) {
		        $( 'html' ).append( data );
	        },
	        type:'GET',
	        url: url
	    } );
    }, //import_templates

    _pag_list_cache : {},
    _pag_hash_cache : {},

    wrap_list:function( args ) {
        return $.yote.templates.data_wrapper( args );
    }, //wrap_list

    wrap_hash:function( args ) {
        return $.yote.templates.data_wrapper( args, true );
    }, //wrap_hash

    data_wrapper:function( args, is_hash ) {
        var arry = args.array;
        var hash = args.hash;
        var size = args.size;
        var key  = args.key || ( args.ctx ? args.ctx.template_path : undefined );

        var node = is_hash ? $.yote.templates._pag_hash_cache[ key ] : $.yote.templates._pag_list_cache[ key ];

        if( ! key || (! node && ( ! arry && ! hash ) ) ) {
            if( is_hash ) 
                throw new Exception( 'wrap hash called without ' + ( key ? 'hash' : 'key' ) );
            else
                throw new Exception( 'wrap list called without ' + ( key ? 'list' : 'key' ) );
        }
        if( ! node ) {
            var start = args.start || 0;
            node = {
                _start : start,
                _page_size  : size,
                _filter_function     : undefined,
                _sort_function       : undefined,
                _transform_function  : undefined,
                set_filter : function( filter_fun ) {
                    this._filter_function = filter_fun;
                },
                set_sort : function( sort_fun ) {
                    this._sort_function = sort_fun;
                },
                set_transform : function( trans_fun ) {
                    this._transform_function = trans_fun;
                },
                can_rewind:function(){
                    return this._start > 0;
                },
                can_fast_forward:function(){
                    return (this._start + this._page_size) < this._data_size;
                },
                back:function(){
                    this._start -= this._page_size;
                    if( this._start < 0 ) {
                        this._start = 0;
                    }
                },
                forwards:function(){
                    this._start += this._page_size;
                    if( this._start >= this._data_size ) {
                        this._start = this._data_size - 1;
                    }
                },
                first:function(){
                    this._start = 0;
                },
                last:function(){
                    this._start = this._data_size - this._page_size;
                    if( this._start < 0 ) {
                        this._start = 0;
                    }
                },
                set_size : function( newsize ) {
                    this._page_size = Number(newsize);
                },
                to_list : function() {
                    var ret
                    if( typeof this._filter_function !== 'undefined' ) {
                        ret = [];
                        for( var i=0, len = this._arry.length; i<len; i++ ) {
                            if( this._filter_function( this._arry[ i ], i, this._arry ) ) {
                                ret.push( this._arry[ i ] );
                            }
                                
                        }
                    } else {
                        ret = this._arry.slice( 0 );
                    }
                    if( typeof this._sort_function !== 'undefined' ) {
                        ret = ret.sort( this._sort_function );
                    }
                    if( typeof this._start !== 'undefined' || typeof this._page_size !== 'undefined' ) {
                        if( typeof this._page_size !== 'undefined' ) 
                            ret = ret.slice( this._start, this._start + this._page_size );
                        else
                            ret = ret.slice( this._start );
                    }
                    return ret;
                },
                keys : function() {
                    var ret = Object.keys( this._hash );
                    if( typeof this._filter_function !== 'undefined' ) {
                        var new_ret = [];
                        for( var i=0, len = ret.length; i<len; i++ ) {
                            var k = ret[ i ];
                            if( this._filter_function( k, this._hash[ k ] ) )
                                new_ret.push( k );
                        }
                        ret = new_ret;
                    } 
                    ret = ret.sort( this._sort_function );
                    if( typeof this._start !== 'undefined' || typeof this._page_size !== 'undefined' ) {
                        if( typeof this._page_size !== 'undefined' ) 
                            ret = ret.slice( this._start, this._start + this._page_size );
                        else
                            ret = ret.slice( this._start );
                    }
                    return ret;
                },
                to_hash : function() {
                    var h = this._hash; 
                    var r = {};
                    var k = this.keys();
                    for( var i=0, len=k.length; i<len; i++ ) {
                        r[ k[i] ] = h[ k[i] ];
                    }
                    return r;
                }
            };
            if( is_hash )
                $.yote.templates._pag_hash_cache[ key ] = node;
            else
                $.yote.templates._pag_list_cache[ key ] = node;
        }

        if( arry ) {
            node._arry = arry;
            node._data_size = arry.length;
        }
        if( hash ) {
            node._hash = hash;
            node._data_size = Object.keys( hash ).length;
        }
        return node;
    }, //data_wrapper
        
    register_template:function( key, value ) {
	    $.yote.templates._compile_template( key, value );
    }, //register template

    _compile_template:function( key, value ) {
	    // fun list = a list of ( priority, function ) couples
	    var fun_list = $.yote.templates._parse_template( value, key );
	    
	    // sort the indexes of the fun list with the indexes of the highest priority functions coming first
	    var idxs = [];
	    for( var i=0, len=fun_list.length; i < len; i++ ) {
	        idxs.push( i );
	    }
	    idxs.sort( function( a, b ) {
	        // lower numbers go first
	        return fun_list[ a ][ 0 ] - fun_list[ b ][ 0 ];
	    } );

	    //build tuples in a list [ [ positi onal idx, function, is_text, is_after_render ], ... ]
	    var compiled = [];
	    for( var i=0, len=idxs.length; i<len; i++ ) {
	        var idx = idxs[ i ];
	        var priority = fun_list[ idx ][ 0 ];
	        var fun_pair = fun_list[ idx ][ 1 ];
	        ((function( item ) {
		        if( priority == 8 ) { //after render priority
		            compiled.push( [ idx, function( ctx ) { return function() { item( ctx ); } }, false, true ] );
		        } else if( priority == 7 ) { //raw text
		            compiled.push( [ idx, item, true, false ] );
		        } else if( priority == 3 || priority == 0 ) { //building functions, so process results again
		            compiled.push( [ idx, function( ctx ) {
			            var ret = $.yote.templates.fill_template_direct( item( ctx ), ctx, key ); 
			            return ret;
		            }, false, false ] );
		        } else { // build with a function that returns
		            compiled.push( [ idx, function( ctx ) { return item( ctx ) }, false, false ] );
		        }
	        } )( fun_list[ idx ][ 1 ] ))
	    }
	    $.yote.templates._compiled_templates[ key ] = compiled;
    }, // _compile_template

    _parse_args: function( arg_txt ) {
        var sing_pos = arg_txt.indexOf( "'" );
        var double_pos = arg_txt.indexOf( '"' );
        if( sing_pos >= 0 || double_pos >= 0 ) {
            if( ( sing_pos > double_pos && double_pos >= 0 ) || sing_pos == -1 ) {
                var parts = arg_txt.match( /^([^"]*)"([^"\\]*(\\.[^"\\]*)*)"([\s\S]*)/ );
            } else {
		        parts = arg_txt.match( /^([^']*)'([^'\\]*(\\.[^'\\]*)*)'([\s\S]*)/ );
            }
            if( parts.length == 5 ) {
                var ret;
		        if( parts[1].trim().length > 0 ) {
		            ret = parts[ 1 ].trim().split( /\s+/ );
                    ret.push( parts[ 2 ] );
		        } else {
		            ret = [ parts[ 2 ] ];
		        }
		        if( parts[ 4 ].trim().length > 0 ) {
		            var newparts = $.yote.templates._parse_args( parts[ 4 ] );
                    ret.push.apply( ret, newparts );
		        }
                return ret;
            }
	        throw new Error( "improperly escaped string in args '" + arg_txt + "'" );
        }
        return arg_txt.trim().split( /\s+/ );
    }, // _parse_args

    _to_function:function( str ) {
        var funparts = str.match( /^\s*function\s*\(([^\),]+)[^)]*\)\s*\{([\s\S]*)\}\s*$/ );
        if( funparts && funparts.length == 3 )
            return new Function( 'var ' + funparts[ 1 ] + ' = arguments[0];' + funparts[ 2 ] );
        // assumed to be the function without 'function( ctx )' 
        return new Function( 'var ctx = arguments[0];' + str );
    }, //_to_function

    // 0 : ???, 1 : $$$, 2 : ??, 4: $$, 5 : $, 6 : raw text, 7 : ?
    _parse_template:function( template_txt, template_name, recurse ) {
        // clear out comments
        //if( $.yote.templates.debug ) return;
        if( ! recurse ) {
	        while( template_txt.indexOf( '<#' ) > -1 ) {
	            var parts = $.yote.templates._template_parts( template_txt, '#', template_name );
                template_txt =  parts[ 0 ] + parts [ 2 ];
	        }

	        recurse = 0;
	    }

        // function to add to template text before other tag types are processed
	    if( recurse < 2 && template_txt.indexOf( '<???' ) > -1 ) {
	        var parts = $.yote.templates._template_parts( template_txt, '???', template_name );
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 2 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 1 );
	        try { 
                var f = $.yote.templates._to_function( parts[1] );
                A.push( [ 0, f ] );
                A.push.apply( A, B );
                return A;
	        }
            
	        catch( err ) {
		        console.log( "Error in compiling '" + template_name + "' in function <??? " + parts[1] + " ???> : " + err);
                A.push.apply( A, B );
	        }
	    } // ???

        // register controls
	    if( recurse < 3 && template_txt.indexOf( '<$$$' ) > -1 ) {
	        var parts = $.yote.templates._template_parts( template_txt, '$$$', template_name );
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 3 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 2 );
            A.push( [ 1, function( ctx ) { return $.yote.templates._register( parts[ 1 ], ctx )  } ] );
            A.push.apply( A, B );
            return A;
	    } // $$$

        // function to add to template text after controls have been registered
        if( recurse < 4 && template_txt.indexOf( '<??' ) > -1 ) {
	        var parts = $.yote.templates._template_parts( template_txt, '??', template_name );
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 4 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 3 );
	        try { 
		        var f = $.yote.templates._to_function( parts[1] );
                A.push( [ 3, f ] );
                A.push.apply( A, B );
                return A;
	        }
            
	        catch( err ) {
		        console.log( "Error in compiling '" + template_name + "' in function <?? " + parts[1] + " ??> : " + err);
                A.push.apply( A, B );
	        }
	    } // ??

	    // fill template
	    if( recurse < 7 && template_txt.indexOf( '<$$' ) > -1 ) {
	        var parts = $.yote.templates._template_parts( template_txt, '$$', template_name );
	        var args = $.yote.templates._parse_args( parts[1] );
            var tmpl = args.shift();
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 7 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 6 );
            A.push( [ 5, function( ctx ) { return $.yote.templates.fill_template( tmpl, ctx, args )  } ] );
            A.push.apply( A, B );
            return A;
	    } // $$

	    // place variable
	    if( recurse < 8 && template_txt.indexOf( '<$' ) > -1 ) {
	        var parts = $.yote.templates._template_parts( template_txt, '$', template_name );
	        var args = $.yote.templates._parse_args( parts[1] );
            var vari = args.shift();
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 8 );
            var B = $.yote.templates._parse_template( parts[ 2 ], template_name, 7 );
            A.push( [ 6, function( ctx ) { return $.yote.templates.fill_template_variable( vari, ctx, args )  } ] );
            A.push.apply( A, B );
            return A;
	    }

	    // functions to be run after rendering is done
	    if( recurse < 9 && template_txt.indexOf( '<?' ) > -1 ) {
	        var parts = $.yote.templates._template_parts( template_txt, '?', template_name );
            var A = $.yote.templates._parse_template( parts[ 0 ], template_name, 8 );
            A.push.apply( A, $.yote.templates._parse_template( parts[ 2 ], template_name, 7 ) );
	        try { 
		        var fun = $.yote.templates._to_function( parts[1] );
		        A.push( [ 8, fun ] ); //can be put on the end as this doesn't change the html rendered
	        }
	        catch( err ) {
		        console.log( "Error compiling after render function in template '" + template_name + "' : '" + err + "' for funtion '" + parts[ 1 ] + "'" );
	        }
	        return A;
	    } // <?
	    
	    if( typeof template_txt === 'string' )
            return [ [ 7, template_txt ] ];
	    return [ ];
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
	        if( ! $.yote.templates._compiled_templates[ templ_name ] ) {
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
	    for( var i=0, len=$.yote.templates._after_render_functions.length; i < len; i++ ) {
	        $.yote.templates._after_render_functions[ i ]();
	    }

	    // reset so next refresh is clean
	    $.yote.templates._after_render_functions = [];
    }, //init

    scratch : {}, // all context objects have a reference to this called scratch, so ctx.scratch

    new_context:function() {
	    return {
	        vars : {},
	        controls : {},
	        args : [], // args passed in to the template as it was built
            parent : undefined,
	        scratch : $.yote.templates.scratch, // reference to common scratch area. 
	        _app_ : $.yote.fetch_default_app(),
	        _acct_ : $.yote.fetch_account(),
	        get: function( key ) { return typeof this.vars[ key ] === 'undefined' ? 
                                   ( key == '_app_' ? $.yote.fetch_default_app() : key == '_acct_' ? 
                                     $.yote.fetch_account() :
                                     undefined ) 
                                   : this.vars[ key ]; },
	        id:$.yote.templates._next_id(),
            refresh : $.yote.templates.refresh,
            parse : function( vari ) {
                return $.yote.templates._parse_val( vari, this, true )
            },
	        clone : function() {
		        var clone = {
		            vars     : Object.clone( this.vars ),
		            id       : $.yote.templates._next_id(),
		            controls : Object.clone( this.controls ),
		            args     : Object.clone( this.args ),
                    refresh  : this.refresh,
		        }; //TODO : add hash key and index
		        clone.clone = this.clone;
		        clone._app_ = this._app_;
		        clone._acct_ = this._acct_;
		        clone.parent = this;
                clone.parse = this.parse;
		        clone.get = this.get;
		        clone.scratch = $.yote.templates.scratch;
		        return clone;
	        } //clone
	    };
    }, //new_context

    fill_template:function( template_name, old_context, args ) {
	    var compilation = $.yote.templates._compiled_templates[ template_name ];	
	    if( ! compilation ) { 
	        console.log( "Error : Template '" + template_name + '" not found.' );
	        return ''; 
	    }
	    var context = old_context ? old_context.clone() : $.yote.templates.new_context();
	    context.template_id = $.yote.templates._next_id();
	    if( old_context ) {
	        context.template_path = old_context.template_path + '/' + template_name;
	    } else {
	        context.template_path = '/' + template_name;
	    }
	    context.args = args;


	    var res = [];
	    for( var i=0, len=compilation.length; i < len; i++ ) {
		    var tuple = compilation[ i ];
		    var idx   = tuple[ 0 ];
		    if( tuple[ 2 ] ) { // is text
		        res[ idx ] = tuple[ 1 ];
		    } else if( tuple[ 3 ] ) { // is after render
	            try {
		            $.yote.templates._after_render_functions.push( tuple[ 1 ]( context ) ); // builds function with context baked in
		            res[ idx ] = '';
	            } catch( err ) {
	                console.log( "Runtime Error filling template '" + template_name + ":" + err + ' in function : ' + tuple[1] );
	            }
		    } else { //function
	            try {
		            res[ idx ] = tuple[ 1 ]( context );
	            } catch( err ) {
	                console.log( "Runtime Error filling template '" + template_name + " : " + err + ' in function : ' + tuple[1]);
	            }
		    }
	    } 

	    return res.join('');
    }, //fill_template

    fill_template_direct:function( template, context, template_name ) {
        if( ! template ) return '';
	    template += '';

	    while( template.indexOf( '<#' ) > -1 ) {
	        var parts = $.yote.templates._template_parts( template, '#', template_name );
	        template = parts[ 0 ] + parts [ 2 ];
	    }

	    // function buliding template ( highest precidence )
	    while( template.indexOf( '<???' ) > -1 ) {
	        var parts = $.yote.templates._template_parts( template, '???', template_name );
	        try { 
		        var f = $.yote.templates._to_function( parts[1] );
                var txt = f( context );
		        template = parts[ 0 ] + ( typeof txt === 'undefined' ? '' : txt ) + parts[ 2 ];
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
		        var f = $.yote.templates._to_function( parts[1] );
                var txt = f( context );
		        template = parts[ 0 ] + ( typeof txt === 'undefined' ? '' : txt ) + parts[ 2 ];
	        }
	        catch( err ) {
		        console.log( "Error in '" + context.template_path + "' in function '" + parts[1] + "' : " + err);
		        template = parts[ 0 ] + parts[ 2 ];
	        }
	    } // ??

	    // fill template
	    while( template.indexOf( '<$$' ) > -1 ) {
	        var parts = $.yote.templates._template_parts( template, '$$', template_name );
	        var args = $.yote.templates._parse_args( parts[1] );
	        var template_name = args.shift();
	        template = parts[ 0 ] +
		        $.yote.templates.fill_template( template_name, context, args ) +
		        parts[ 2 ];
	    } // $$

	    // place variable
	    while( template.indexOf( '<$' ) > -1 ) {
	        var parts = $.yote.templates._template_parts( template, '$', template_name );
	        var args = $.yote.templates._parse_args( parts[1] );
	        var vari = args.shift();
	        template = parts[ 0 ] +
		        $.yote.templates.fill_template_variable( vari, context, args ) +
		        parts[ 2 ];
	    }
	    while( template.indexOf( '<?' ) > -1 ) {
	        // functions to be run after rendering is done
	        var parts = $.yote.templates._template_parts( template, '?', template_name );
	        try { 
		        var fun = $.yote.templates._to_function( parts[1] );
		        $.yote.templates._after_render_functions.push( 
		            (function( f, ctx ) { return function() { 
			            try { 
			                alert( 'need context bottled up...need to  have a template registry path --> template' );
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
    }, //fill_template_direct
    

    // fill
    _template_parts:function( txt, sigil, template_name ) {
	    var rev_sigil = sigil.split('').reverse().join('');
	    var start = txt.indexOf( '<' + sigil );
	    var end   = txt.indexOf( rev_sigil + '>' );
	    if( end == -1 ) throw new Error( "Error, mismatched template start and end sigils (" + sigil + ") for template '" + template_name + "' : " + txt );
	    var len   = sigil.length + 1;

	    // recalculate the start if need be...this chunk should not have two 
	    // starts in a row..actally just reverse the string and find the 
	    // first rev_sigel...so
	    //   '<$$ <$$ foo bar $$>' ---> <$$ rab oof $$> $$>
	    //                          end ^           ^ lenstring - indexof rev is start
	    // however, the while loop will work as well
	    
	    while( txt.substring( start + len, end ).indexOf( '<' + sigil ) >= 0 ) {
            if( txt.substring( start + len, end ).indexOf( '<' + sigil ) < start ) {
	            console.log( "Template error for '"+template_name+"' : unable to find close of <" + sigil + ' : ' + txt );
	            return;
            }
	        start = txt.substring( start + len, end ).indexOf( '<' + sigil );
	    }

	    if( end < start ) {
	        console.log( "Template error for '"+template_name+"' : unable to find close of <" + sigil + ' : ' + txt);
	        return;
	    }
	    return [ txt.substring( 0, start ),
		         txt.substring( start + len, end ).trim(),
		         txt.substring( end+len ) ];
    }, //_template_parts
    
    // pass in a value/variable (calling this vavar) name string, a context and a boolean.
    // if the boolean is false, then if the vavar name is not defined in the context, it is returned literally
    // so   _parse_val( "FOO", { context object with foo defined as "bar" }, true ) --> "bar"
    // so   _parse_val( "FOO", { context object with NOT foo defined }, true ) --> "FOO"
    // in addition, the vavar contains period characters, those are treated as separators.
    //      _parse_val( "foo.bar.baz", { context object with foo object that has a bar object that has a baz field with the value of "yup" } ) --> "yup"
    _parse_val:function( value, context, no_literal ) {
	    var tlist = value.trim().split(/[\.]/);
	    var subj = context;
	    var subj_has_get = true;
	    for( var i=0, len=tlist.length; i < len; i++ ) {
	        var part = tlist[ i ];

            //check if this must be paginated
            var array_pag_pair = part.split( /\@\@/ );
            if( array_pag_pair.length == 2 ) {
                if( array_pag_pair[ 0 ] == '' ) {
                    subj = subj_has_get ? subj.get( array_pag_pair[ 1 ] ).to_list() : subj[ array_pag_pair[ 1 ] ];
                    return $.yote.templates.wrap_list( {
                        array : subj,
                        key : context.template_path + '#' + value,
                    }); //TODO - missing var case, and what if its not at the end?
                } else {
                    part = array_pag_pair[ 0 ];
                }
                var arr_pagname = array_pag_pair[ 1 ];
            }
            else {
                var array_pair = part.split( /\@/ );
                if( array_pair.length == 2 ) {
                    if( array_pair[ 0 ] == '' ) {
                        subj = subj_has_get ? subj.get( array_pair[ 1 ] ).to_list() : subj[ array_pair[ 1 ] ];
                        return subj; //TODO - missing var case, and what if its not at the end?
                    } else {
                        part = array_pair[ 0 ];
                    }
                    var arrname = array_pair[ 1 ];
                } else {
                    var hash_pair = part.split( /\%/ );
                    if( hash_pair.length == 2 ) {
                        if( hash_pair[ 0 ] == '' ) {
                            subj = subj_has_get ? subj.get( hash_pair[ 1 ] ).to_hash() : subj[ hash_pair[ 1 ] ];
                            return subj; //TODO - missing var case, and what if its not at the end?
                        } else {
                            part = hash_pair[ 0 ];
                        }
                        var hashname = hash_pair[ 1 ];
                    }
                }
            }

            if( typeof subj === 'object' ) {
		        subj = subj_has_get ? subj.get( part ) : subj[ part ];
                subj_has_get = $.yote._subj_has_get_p();
	        }
	        if( typeof subj === 'undefined' ) return no_literal ? undefined : value;

            if( arrname ) {
                // TODO - handle missing var case?
                subj = subj_has_get ? subj.get( arrname ).to_list() : subj[ arrname ];
            } else if( hashname ) {
                subj = subj_has_get ? subj.get( hashname ).to_hash() : subj[ hashname ];
            } else if( arr_pagname ) {
                subj = subj_has_get ? subj.get( arr_pagname ).to_list() : subj[ arr_pagname ];
                subj = $.yote.templates.wrap_list( {
                    array : subj,
                    key : context.template_path + '#' + value,
                }); //TODO - missing var case, and what if its not at the end?
            }
	    }
	    return subj;
    }, //_parse_val

    _register:function( args_string, context ) {
        /*
          registers an html control with a unique id and assigns
          the control-name in the controls context to it.

          <$$$ control-name <..html control..> $$$>
        */
	    var parts   = args_string.match( /^\s*(\S+)(\s+\S[\s\S]*)?/ );
	    var varname = parts ? parts[ 1 ] : undefined;
	    var rest    = parts ? parts[ 2 ] : undefined;

        // check to see if the control already has an id or not.
        // assign an id if it does not.
	    var ctrl_parts = /\*\<[\s\S]* id\s*=\s*['"]?(\S+)['"]? /.exec( rest );
	    var ctrl_id;
	    if( ctrl_parts ) {
		    ctrl_id = ctrl_parts[ 1 ];
	    }
	    else {
		    ctrl_id = $.yote.templates._next_id();
            if( rest )
		        rest = rest.replace( /^\s*(<\s*[^\s\>]+)([ \>])/, '$1 id="' + ctrl_id + '" $2' );
        }
	    context.controls[ varname ] = '#' + ctrl_id;
	    return rest;

        return '';

    }, //_register


    fill_template_variable:function( vari, context, args ) {
	    //   $.yote.templates._parse_val returns 
	    var res = $.yote.templates._parse_val( vari, context, true );
	    return typeof res === 'undefined' ? args[ 0 ] ? args[ 0 ] : '' : res;
    }, //fill_template_variable


}//$.yote.templates
