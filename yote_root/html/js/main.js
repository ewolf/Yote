var menu_list = [ [ 'About',      'index.html' ],
		  [ 'Install',    'install.html' ],
		  [ 'Quickstart', 'quickstart.html' ],
		  [ 'Docs',       'docs.html' ],
		  [ 'Samples',    'samples.html' ]
		];

function make_menus( attach_point ) {
    var current_page = document.URL.match( /\/([^\/]*?)(\#.*)?$/ )[ 1 ];

    var buf = '';
    for( var i=0; i<menu_list.length; i++ ) {
	if( current_page == menu_list[ i ][ 1 ] ) {
	    buf += '<LI><A class="active" HREF="' + menu_list[ i ][ 1 ] + '">' + menu_list[ i ][ 0 ] + '</A></LI>';
	} else {
	    buf += '<LI><A HREF="' + menu_list[ i ][ 1 ] + '">' + menu_list[ i ][ 0 ] + '</A></LI>';
	}
    }
    $( attach_point ).empty().append( buf );

} //make_menus

function msg( message ) {
    alert( message );
}
