UIMaster = {

    init:function( attachpoint ) {
	$( attachpoint ).mousemove(
	    
	);
	$( attachpoint ).mouseenter(
	    var ctrls = this._controls_under_mouse( event.pageX, event.pageY );
	    for( var idx in ctrls ) {
		ctrls[idx].mouseenter( event.pageX, event.pageY );
	    }
	);

	$( attachpoint ).mouseleave(
	    var ctrls = this._controls_under_mouse( event.pageX, event.pageY );
	    for( var idx in ctrls ) {
		ctrls[idx].mouseleave( event.pageX, event.pageY );
	    }
	);

	$( attachpoint ).mouseup(
	    var ctrls = this._controls_under_mouse( event.pageX, event.pageY );
	    this.ctrls_under = ctrls;
	    for( var idx in ctrls ) {
		ctrls[idx].mouseup( event.pageX, event.pageY );
	    }
	);

	$( attachpoint ).mousedown(
	    var ctrls = this._controls_under_mouse( event.pageX, event.pageY );
	    for( var idx in ctrls ) {
		ctrls[idx].mousedown( event.pageX, event.pageY );
	    }
	);

	$( attachpoint ).mouseclick( function( event ) {
	    var ctrls = this._controls_under_mouse( event.pageX, event.pageY );
	    for( var idx in ctrls ) {
		ctrls[idx].mouseclick( event.pageX, event.pageY );
	    }
	} );
    },

    _active_sprite:undefined,

    _active_control:undefined,

    _sprites_under_mouse:function( X, Y ) {
    },

    _controls_under_mouse:function( X, Y ) {
    },

    _topid:0,

    _sprites:{},

    _controls:{},

    make_sprite:function() {
	var id = _topid++;
	var sprite = {
	    id:id,
	    master:this,
	    data:undefined,
	    attached_to_control:undefined,
	    html_render:function() {},
	    mouseenter:function( X, Y ) {
		$( '#_' + this.id ).addClass( 'mouseover' );
	    },
	    mouseleave:function( X, Y ) {
		$( '#_' + this.id ).removeClass( 'mouseover' );
	    },
	};
	this._sprites[id] = sprite;
	return sprite;
    },

    make_control:function() {
    },

}; //UIMaster