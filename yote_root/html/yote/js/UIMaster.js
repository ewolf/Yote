var UIMaster = {
    o:'master',
    control_under_mouse:undefined,
    sprite_under_mouse:undefined,
    active_sprite:undefined,
    active_control:undefined,
    lastX:0,
    lastY:0,
    init:function( attachpoint ) {
        this.selector = ( function(ap) { return function() { return $( ap ) } } )( attachpoint );
        // mousemove event is used to find what controls and sprites the mouse is under.
        //   it calls mouseenter, mouseleave and mousemove events on the controls and sprites
        $( attachpoint ).mousemove( (function(master) {
	    return function( event ) {
                var X = event.pageX; var Y = event.pageY;
                var ctrl = master.find_control_under_mouse( X, Y );
                if( ctrl ) {
		    if( master.active_control ) {
                        if( master.active_control !== ctrl ) {
			    master.active_control.mouseleave( X, Y );
                        }
                        ctrl.mousemove( X, Y );
		    } else {
                        ctrl.mouseenter( event.pageX, event.pageY );
                        master.active_control = ctrl;
		    }
                } else if ( master.active_control ) {
		    master.active_control.mouseleave( X, Y );
                }

                var sprite = master.find_sprite_under_mouse( X, Y );
                if( sprite ) {
		    if( master.over_sprite ) {
                        if( master.over_sprite !== sprite ) {
			    master.over_sprite.mouseleave( X, Y );
			    master.over_sprite = sprite;
                        }
                        sprite.mousemove( X, Y );
		    } else {
                        sprite.mouseenter( event.pageX, event.pageY );
                        master.over_sprite = sprite;
		    }
                }
                if ( master.active_sprite ) {
		    master.active_sprite.mousemove( X, Y );
                }
                master.lastX = X;
                master.lastY = Y;

	    } } )( this ) ); // init - mousemove

        // mouseup event signals a sprite is being let go.
        //  this event gives a sprite from one control to the other or bounces sprite back to active control
        //  and then clears the active_sprite field
        $( attachpoint ).mouseup( (function(master) {
	    return function( event ) {
                if( master.active_sprite ) {
		    if( master.control_under_mouse ) {
                        if( master.active_control != master.control_under_mouse) {
			    master.active_control.give_sprite_to_control( master.active_sprite, master.control_under_mouse );
			    master.active_control = master.control_under_mouse;
                        } else { //same control
			    master.control_under_mouse.accept_sprite_from_self( master.active_sprite );
                        }
		    } else if(  master.active_control ) {

                        master.active_control.accept_sprite_from_self( master.active_sprite );
		    }
		    master.active_sprite = undefined;
                }
	    }
        } )( this ) ); // init - mouseup

        // mousedown event signals a sprite is being picked up.
        //  this event sets the active sprite
        $( attachpoint ).mousedown( (function(master) {
	    return function( event ) {
                master.lastX = event.pageX;
                master.lastY = event.pageY;
                master.active_sprite = master.sprite_under_mouse;
                master.active_control = master.control_under_mouse;
                if( master.active_sprite ) {
		    master.active_sprite.origOffset = master.active_sprite.selector().offset();
                }
	    }
        } )( this ) ); // init - mousedown

        // click events signals that a control is to be activated. its click method is called
        //
        $( attachpoint ).click( (function(master) {
	    return function( event ) {
                if( master.control_under_mouse ) {
		    master.control_under_mouse.click( event.pageX, event.pageY );
                }
                if( master.sprite_under_mouse ) {
		    master.sprite_under_mouse.click( event.pageX, event.pageY );
                }
	    }
        } )( this ) ); // init - click
    }, //init

    // this discovers which sprite is under the mouse. with the highest priority
    find_sprite_under_mouse:function( X, Y ) {
        var sprite;
        for( var idx in this.sprites ) {
	    var sp = this.sprites[idx];
	    var os = sp.selector().offset();
	    var w = sp.selector().width();
	    var h = sp.selector().height();
	    if( sp != this.active_sprite &&
                os.left <= X && ( os.left + w ) >= X &&
                os.top <= Y && ( os.top + h ) >= Y ) {
                if( sprite ) {
		    if( sprite.priority < sp.priority ) {
                        sprite = sp;
		    }
                } else {
		    sprite = sp;
                }
	    }
        } 
        this.sprite_under_mouse = sprite;
        return sprite;
    }, //find_sprite_under_mouse

    find_control_under_mouse:function( X, Y ) {
        var ctrl;
        for( var idx in this.controls ) {
	    var ct = this.controls[idx];
	    var os = ct.selector().offset();
	    var w = ct.selector().width();
	    var h = ct.selector().height();
	    if( os.left <= X && ( os.left + w ) >= X &&
                os.top <= Y && ( os.top + h ) >= Y ) {
                if( ctrl ) {
		    if( ctrl.priority < ct.priority ) {
                        ctrl = ct;
		    }
                } else {
		    ctrl = ct;
                }
	    }
        }
        this.control_under_mouse = ctrl;
        return ctrl;
    }, //find_control_under_mouse
    
    topid:0,

    sprite_selectors:{},
    sprites:{},

    controls:{},

    make_sprite:function() {
        var id = this.topid++;
        var sprite = {
	    o:'sprite',

	    id:id,
	    selector:function() { return $( '#_' + id ); },
	    sprite_id:function() { return '_' + id; },
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
	    click:function( X, Y ) {},
	    mousemove:function( X, Y ) {}
        };
        this.sprites[id] = sprite;
        return sprite;
    }, //make_sprite

    make_control:function() {
        var id = this.topid++;
        var control = {
	    o:'control',

	    id:id,

	    control_id:function() { return '_' + id; },

	    selector:function() { return $( '#_' + id ); },

	    master:this,

	    data:undefined,

	    html_render:function() {},

	    sprites:[],

	    update_sprites:function() {},

	    can_accept_sprite:function( sprite, control ) {
                return true;
	    },

	    accept_sprite:function( sprite ) {
                this.selector().append( this.master.sprite_selectors[ sprite.id ] );
                this.sprites.push( sprite );
	    },

	    accept_sprite_from_control:function( sprite, control, offset ) {
                this.selector().append( this.master.sprite_selectors[ sprite.id ] );
		sprite.selector().offset( { left:offset.left, top:offset.top } );
                this.sprites.push( sprite );
                this.update_sprites();
	    },

	    accept_sprite_from_self:function( sprite ) {
                this.update_sprites();
	    },

	    give_sprite_to_control:function( sprite, control ) {
                if( control.can_accept_sprite( sprite, this ) ) {
		    for( var idx in this.sprites ) {
                        if( this.sprites[idx].id == sprite.id ) {
			    this.sprites.splice( idx, 1 );
			    break;
                        }
		    }
		    var offset = sprite.selector().offset();
		    UIMaster.sprite_selectors[sprite.id] = sprite.selector().detach();
		    control.accept_sprite_from_control( sprite, this, offset );
                } 
		this.update_sprites();
	    },

	    mouseenter:function( X, Y ) {
                $( '#_' + this.id ).addClass( 'mouseover' );
	    },

	    mouseleave:function( X, Y ) {
                $( '#_' + this.id ).removeClass( 'mouseover' );
	    },

	    click:function( X, Y ) {},

	    mousemove:function( X, Y ) {}
        };
        this.controls[id] = control;
        return control;
    }, //make_control


    make_title_sprite:function( title ) {
	var sprite = UIMaster.make_sprite();
	sprite.title = title;
	sprite.mousemove = (function(s) { return function( X, Y ) {
	    if( s.master.active_sprite === s ) {
		var o = s.selector().offset();
		s.selector().offset( {
		    left:o.left + ( X - s.master.lastX ),
		    top:o.top   + ( Y - s.master.lastY ) } );
	    }
	} } )( sprite );//mousemove
	UIMaster.selector().append( '<div id=' + sprite.sprite_id() + ' style="width:100;height:40;background-color:lightyellow;border:1px solid black">' + title + '</div>' );
	sprite.selector().css('z-index',1);
	UIMaster.sprite_selectors[sprite.id] = sprite.selector().detach();
	return sprite;
    }, //make_title_sprite


    make_list_box:function( list ) {

	var ctrl = UIMaster.make_control();

	ctrl.render_sprites = function() {

	}

	ctrl.update_sprites = function() {
	    this.sprites.sort( function(a,b) {
		return a.selector().offset().top - b.selector().offset().top;
	    } );
	    var X      = this.selector().offset().left + 5;
	    var startY = this.selector().offset().top + 5;
	    for( idx in this.sprites ) {
		this.sprites[idx].selector().offset( { left:X, top:startY } );
		startY = this.sprites[idx].selector().offset().top + this.sprites[idx].selector().height() + 5;
	    }
	}

	UIMaster.selector().append( '<div id=' + ctrl.control_id() + '></div>' );

	for( var idx in list ) {
	    ctrl.accept_sprite( UIMaster.make_title_sprite( list[idx] ) );
	}

	return ctrl;

    }, //make_list_box
}; //UIMaster
