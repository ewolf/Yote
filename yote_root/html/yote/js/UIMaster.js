var UIMaster = {
    
    items : [],

    item_under_mouse : function( X, Y ) {
	var ret = undefined;
	for( var idx in this.items ) {
	    var itm = this.items[ idx ];
	    if( Y >= itm.top()  && Y <= itm.bottom() &&
		X >= itm.left() && X <= itm.right() )
	    {
		if( (! ret) || ret.priority < itm.priority ) {
		    ret = itm;
		}
	    }
	}
	return ret;
    }, //item_under_mouse

    init:function( attachpoint ) {

        this.selector = ( function(ap) { return function() { return $( ap ) } } )( attachpoint );

	

        $( attachpoint ).mousemove( (function(master) {
	    return function( event ) {
                var X = event.pageX; var Y = event.pageY;

		var item = master.item_under_mouse( X, Y );

		if( item ) {
		    if( master.over == item ) {
			item.mouse_move( X, Y );
		    } else if( master.over ) {
			master.over.mouse_leave( X, Y );
			item.mouse_enter( X, Y );
		    } else {
			item.mouse_enter( X, Y );			
		    }			
		} else if( master.over ) {
		    master.over.mouse_leave( X, Y );
		}
		if( master.holding ) {
		    master.holding.mouse_move( X, Y );
		}
	    } } ) ( this ) ); // init - mousemove
    }, //init
    
    make_item:function() {
	var id = items.length;
	var itm {
	    id:id,
	    selector:function() { return $( '#_' + this.id ); },
	    offset:function() { return this.selector().offset(); },
	    top:function() { return this.offset().top; },
	    left:function() { return this.offset().left; },
	    bottom:function() { return this.top() + this.selector().height; },
	    right:function() { return this.left() + this.selector().width; },
	    mouse_move:function( X, Y ) {},
	    mouse_enter:function( X, Y ) {},
	    mouse_leave:function( X, Y ) {},
	    mouse_up:function( X, Y ) {},
	    mouse_down:function( X, Y ) {},
	    click:function() {},
	    accepts:function( item, X, Y ) {},
	    accept:function( item, control, X, Y ) {},
	    give:function( item, control, X, Y ) {},
	};
	return itm;
    }, //make_item

}; //UIMaster
