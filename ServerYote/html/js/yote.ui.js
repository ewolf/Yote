if( yote ) {

    var _costForm = new Intl.NumberFormat( "en-US", {
        minimumFractionDigits : 2,
        maximumFractionDigits : 2,              
        style : "decimal",
    } );

    var _makeFormatter = function( decimals ) {
        return new Intl.NumberFormat( "en-US", {
            minimumFractionDigits : decimals,
            maximumFractionDigits : decimals,
            style : "decimal",
        } );
    }
    
    var _updater = function(o) {

        $( ".toggleField" ).each( function() {
            var obj = o;
            var $this = $(this);
            if( $this.attr('data-id') != obj.id ) {
                return;
            }

            var fld = $this.attr( 'data-field' );
            var tClass = $this.attr( 'data-toggle-class' );
            $this.toggleClass( tClass, o.get( fld ) ? true : false );
            
        } );

        $( ".showField" ).each( function() {
            var obj = o;
            var $this = $(this);
            if( $this.attr('data-id') != obj.id ) {
                return;
            }

            var fld = $this.attr( 'data-field' );
            var val = o.get( fld );

            var form = $this.attr( 'data-format' );
            if( form ) {
                if(  form == '$' ) {
                    val = _costForm.format( val );
                }
                else if( form.startsWith('#') ) {
                    val = _makeFormatter( $this.attr( 'data-format').substr( 1 ) ).format( val );
                }
            }
            if( $this.is( 'input' ) ) {
                var t = $this.attr('type');
                if( $this.attr( 'type' ) === 'checkbox' ) {
                    if( val === "1" ) {
                        $this.prop( 'checked', true );
                    } else {
                        $this.prop( 'checked', false );
                    }
                } else {
                    $this.attr( 'value', val );
                }
            } else if( $this.is( 'select' ) ) {
                if( typeof val === 'object' ) {
                    $this.val( val.id );
                } else {
                    $this.val( val );
                }
            } else if( $this.is( 'img' ) ) {
                $this.attr( 'src', val );
            } else if( val ) {
                $this.text( val );
            } else {
                $this.html( '&nbsp;' );
            }
        } );
    }; //_updater

    yote.ui = {

          energize : function( cls, obj ) {
              yote.ui.setIds( cls, obj );
              yote.ui.activateControls();
              yote.ui.watchForUpdates( obj );
          }, 

          fill_template : function( sel, vars, fields ) {
              if( ! fields ) { fields = []; }
              if( ! vars )   { vars = []; }
              var $template = $( 'section.templates ' + sel + '[data-cloned!="true"]' );
              if( $template.length > 1 ) {
                  console.warn( "error filling template '" + sel + "'. selector matches somethign other than one thing." );
                  return undefined;
              } else if( $template.length == 0 ) {
                  console.warn( "error filling template '" + sel + "'. could not find template." );
                  return undefined;
              }
              var $clone = $template.clone();
              $clone.attr( 'data-cloned', 'true' );
              function filler( $this ) {
                  if( $this.is( 'select' ) ) { 
                      console.log( $this );
                  }
                  for( var i=0;i<fields.length; i++ ) {
                      var fld = fields[i];
                      if( typeof vars[$this.attr( fld )] !== 'undefined' ) {
                          $this.attr( fld, vars[$this.attr( fld )] );
                      }
                  }
              };
              filler( $clone );
              $clone.find("*").each( function() {
                  filler( $(this) );
              } );
              return $clone;
          }, //fill_template

          setIds : function( cls, obj ) {
              $( '.' + cls + ',.'+cls+'-child' ).each( function() {
                  var $this = $(this);

                  $this.attr( 'data-redo', true );
                  if( $this.is( 'select' ) && $this.attr( 'data-id' ) != obj.id ) {
                      // special casey thing to regenerate select controls
                      $this.removeClass( 'build-select' );
                  }
                  if( $this.hasClass( cls+'-child' ) ) {
                      $this.attr( 'data-parent', obj.id );
                  }
                  if( $this.hasClass( cls ) ) {
                      $this.attr( 'data-id', obj.id );
                  }
              } );
          },

          updateListener : function( obj, listenerName, listenerFunc, runOnStartup ) {
              if( ! obj[ listenerName ] ) {
                  obj[ listenerName ] = true;
                  obj.addUpdateListener( listenerFunc );
              }
              if( runOnStartup ) {
                  listenerFunc( obj );
              }
          }, //updateListener

          modifyControl : function( selector, key, fun ) {
              if( typeof key === 'object' ) {
                  for( var k in key ) {
                      yote.ui.modifyControl( selector, k, key[k] );
                  }
                  return;
              }
              $( selector ).each( function(idx,val) {
                  var $this = $( val );
                  if( ! $.contains( $('.templates')[0], val ) ) {
                      if( (! $this.attr( 'data-' + key ) || $this.attr( 'data-redo' ) ) && $this.attr( 'data-id') ) {
                          $this.attr( 'data-redo', false );
                          $this.attr( 'data-' + key, true );
                          fun( $this );
                      }
                  }
              } );
          }, //modifyControl

          activateControls : function()  {
              yote.ui.modifyControl( 'div.updateFieldControl', 'updateField-setup', function( $ctrl ) {
                  $ctrl.empty().append( '<input class="updateField showField ' + ($ctrl.attr( 'data-classes') ||'') + '" ' + 
                                        '       data-id="'    + $ctrl.attr( 'data-id') + '"' + 
                                        '       data-field="' + $ctrl.attr( 'data-field' ) + '"' + 
                                        '       type="'       + ( $ctrl.attr( 'data-input-type') || 'text' )+ '">' +
                                        '<span class="showField ' + ($ctrl.attr( 'data-classes')||'') + '"' + 
                                        '      data-id="' + $ctrl.attr( 'data-id') + '"' + 
                                        '      data-format="'+ $ctrl.attr( 'data-format' ) + '"' + 
                                        '      data-field="' + $ctrl.attr( 'data-field') + '">' + 
                                        '  &nbsp;</span>' );
              } );

              yote.ui.modifyControl( 'div.updateFieldControl>span', 'updateField-click', function( $ctrl ) {
                  $ctrl.off( 'click' ).on( 'click',
                            function() {
                                var $this = $(this);
                                $this.parent().addClass( 'editing' );
                                var $inpt = $this.parent().find( 'input' );
                                $inpt.attr( 'data-original', $inpt.val() );
                                $inpt.focus();
                            } );
              } );


              yote.ui.modifyControl( 'div.updateFieldControl', 'updateField-click', function( $ctrl ) {
                  $ctrl.off( 'click' ).on( 'click',
                            function() {
                                var $this = $(this);
                                $this.addClass( 'editing' );
                                var $inpt = $this.find( 'input' );
                                $inpt.attr( 'data-original', $inpt.val() );
                                $inpt.focus();
                            } );
              } );

              yote.ui.modifyControl( 'div.updateFieldControl>input', {
                  'updateField-blur' : function( $ctrl ) {
                      $ctrl.off( 'blur' ).on( 'blur',
                                function(ev) {
                                    var $this = $(this);
                                    if( $this.attr( 'data-original' ) == $this.val() ) {
                                        $this.parent().removeClass( 'editing' );
                                    }
                                } );
                  },
                  'updateField-keydown' : function( $ctrl ) {
                      $ctrl.off( 'keydown' ).on( 'keydown',
                                function(ev) {
                                    var kk = ev.keyCode || ev.charCode;
                                    var $this = $(this);
                                    if( kk == 27 )  {
                                        $this.val( $this.attr( 'data-original' ) );
                                        $this.parent().removeClass( 'editing' );
                                        $this.removeClass('edited' );
                                    } else if( kk == 13 || kk == 9 ) {
                                        ev.preventDeafult();
                                        var p = $this.parent();
                                        p.removeClass( 'editing' );
                                        p.find('span').text( $this.val() );
                                        $this.parent().removeClass( 'editing' );
                                        $this.removeClass('edited' );
                                    }
                                    $this.toggleClass('edited', $this.attr( 'data-original') == $this.val() );
                                } );
                  },
                  'updateField-keyup' : function( $ctrl ) {
                      $ctrl.toggleClass('edited', $ctrl.attr( 'data-original') != $ctrl.val() );
                  }
              } );

              yote.ui.modifyControl( 'select.updateField', 'build-select', function( $ctrl ) {
                  // data : 
                  //   field - field on object to modify
                  //   id - object to modify
                  //   data-src-id     - object where this list comes from
                  //   data-src-field  - 
                  //   data-src-method -

                  var targ_obj = yote.fetch( $ctrl.attr( 'data-id' ) );
                  var targ_fld = $ctrl.attr( 'data-field' );
                  var cur_val    = targ_obj.get( targ_fld );
                  if( $ctrl.attr( 'data-var-is') === 'object' && cur_val ) {
                      cur_val = cur_val.id;
                  }

                  var source_id  = $ctrl.attr( 'data-src-id' );
                  var list;
                  var fillOptions = function() {
                      var buf = '';
                      for( var i=0; i<list.length; i++ ) {
                          var el = list[i];
                          var title, val;
                          if( Array.isArray( el ) ) {
                              val   = el[0];
                              title = el[1];
                          } else {
                              val   = el;
                              title = el;
                          }
                          var dataid = '';
                          if( typeof val === 'object' ) {
                              val = val.id;
                              dataid = 'data-id="' + val + '" data-field="name" ';
                          }
                          if( typeof title === 'object' ) {
                              title = title.get( 'name' );
                          }
                          buf += '<option class="showField" ' + dataid + ' value="' + val + '">' + title + '</option>';
                      }
                      $ctrl.empty().append( buf ).val( cur_val );
                      if( ! buf && $ctrl.attr( 'data-hide-on-empty' ) ) {
                          $ctrl.hide();
                      } else {
                          $ctrl.show();
                      }

                  } //fillOptions

                  var source_obj = source_id ? yote.fetch( source_id ) : targ_obj;
                  if( $ctrl.attr( 'data-src-field' ) ) {
                      var listO = source_obj.get( $ctrl.attr( 'data-src-field' ) );
                      list = listO.toArray();
                      fillOptions();
                  
                      yote.ui.updateListener( listO, 'select-chooser-build-select', function() {
                          var key = 'build-select';
                          $ctrl.attr( 'data-' + key, false );
                          yote.ui.activateControls();
                      }, false );
                  }
                  if( typeof targ_fld !== 'undefined' ) {
                      $ctrl.off( 'change' ).on( 'change',
                                                function( ev ) {
                                                    var val = $ctrl.val();
                                                    if( $ctrl.attr( 'data-var-is') === 'object' ) {
                                                        val = yote.fetch( val );
                                                    }
                                                    var up = {};
                                                    up[ targ_fld ] = val;
                                                    targ_obj.update( [up] );
                                                } );
                  }

              } );
              yote.ui.modifyControl( 'input.updateField[type="checkbox"]', 'checked', function( $ctl ) {
                  $ctl.off( 'change' ).on( 'change', function(ev) {
                      var $this = $( this );
                      var obj = yote.fetch( $this.attr( 'data-id') );
                      var fld = $this.attr( 'data-field');
                      var inpt = {};
                      inpt[ fld ] = $this.is(':checked') ? 1 : 0;
                      obj.update( [ inpt ] );
                  } );
              });
              yote.ui.modifyControl( 'input.updateField', 'input-keydown', function( $ctl ) {
                  $ctl.off( 'keydown' ).on( 'keydown', function(ev) {
                      var kk = ev.keyCode || ev.charCode;
                      if( kk == 13 || kk == 9 ) {
                          var $this = $( this );
                          var obj = yote.fetch( $this.attr( 'data-id') );
                          var fld = $this.attr( 'data-field');
                          var inpt = {};
                          inpt[ fld ] = $this.val() ;
                          obj.update( [ inpt ] );
                      } 
                  } ); // input.updateField
              } );

              yote.ui.modifyControl( '.delAction', 'delAction', function( $this ) {
                  $this.off( 'click' ).on( 'click', function(ev) {
                      ev.preventDefault();
                      if( $this.attr( 'data-needs-confirmation' ) && ! confirm( $this.attr( 'data-delete-message' ) || 'really delete?' ) ) {
                          return;
                      }
                      var par    = yote.fetch($this.attr( 'data-parent' ));
                      var obj    = yote.fetch($this.attr( 'data-id' ));
                      par.remove_entry( [obj,$this.attr( 'data-from')] );
                  } );
              } ); //delAction

              yote.ui.modifyControl( '.addAction', 'addClick', function( $this ) {
                  $this.off( 'click' ).on( 'click', function(ev) {
                      ev.preventDefault();
                      var $this = $(this);
                      var list  = $this.attr( 'data-list');
                      var listOn = yote.fetch( $this.attr( 'data-id') );
                      listOn.add_entry( [ list ], function( newo ) {
                          yote.ui.watchForUpdates( Array.isArray( newo ) ? newo[0] : newo ); } );
                  } );
              } ); //addAction

              // TODO - BE ABLE TO HAVE MULTIPLE CLICK HANDLERS (*sigh*)

              yote.ui.modifyControl( '.action', 'addAction', function( $this ) {
                  $this.off( 'click' ).on( 'click', function(ev) {
                      ev.preventDefault();
                      var $this = $(this);
                      var action  = $this.attr( 'data-action');
                      var params  = [];
                      if( $this.attr( 'data-param') ) {
                          // TODO - for multiple params, a data-number-of-params, then data-param_1, data-param_2 ...
                          params.push( yote.fetch( $this.attr( 'data-param') ));
                      }
                      // TODO - error message for item not found
                      var item = yote.fetch( $this.attr( 'data-id') );
                      item[ action ]( params );
                  } );
              } );
          }, //activateControls

          setup_table : function( args ) {
              var $tab = $( args.conSel ).find( 'tbody' );
              $tab.empty();
              var items = args.list || args.listOn.get( args.listName );
              items.each( function( item, i ) {
                  var replaceList = typeof args.replaceList === 'function' ? args.replaceList( item, i ) : args.replaceList;
                  var row = yote.ui.fill_template( args.rowSel, replaceList || {
                      ID     : item.id,
                      FROMID : args.listOn.id
                  }, args.fieldList || [ 'id', 'parent' ] );
                  
                  $tab.append( row );

                  if( args.onEachRow ) {
                      args.onEachRow( row, item, i );
                  }
                      
                  yote.ui.watchForUpdates(item);
              } );

              yote.ui.activateControls();
              items.each( function( item, i ) {
                  yote.ui.watchForUpdates(item);
              } );
          }, //setup_table

          setup_container : function( args ) {
              var $con = $( args.conSel );
              if( args.isTable ) {
                  var $tBody = $con.find( 'tbody' );
                  if( $tBody ) {
                      $con = $tBody;
                  }
              }
              $con.empty();
              var items = args.list || args.listOn.get( args.listName );
              items.each( function( item, i ) {
                  var replaceList = typeof args.replaceList === 'function' ? args.replaceList( item, i ) : args.replaceList;
                  var row = yote.ui.fill_template( args.rowSel, replaceList || {
                      ID     : item.id,
                      FROMID : args.listOn.id
                  }, args.fieldList || [ 'id', 'parent' ] );
                  
                  $con.append( row );

                  if( args.onEachRow ) {
                      args.onEachRow( row, item, i );
                  }
                      
                  yote.ui.watchForUpdates(item);
              } );

              yote.ui.activateControls();
              items.each( function( item, i ) {
                  yote.ui.watchForUpdates(item);
              } );
          }, //setup_container


          watchForUpdates : function() {
              // if the object changes, all HTML controls displaying data from that object are updated
              for( var i=0; i<arguments.length; i++ ) {
                  var obj = arguments[ i ];
                  if( ! obj._watched ) {
                      obj.addUpdateListener( _updater );
                      obj._watched = true;
                  }
                  _updater( obj );
              }
          } //watchForUpdates
    };
} 
