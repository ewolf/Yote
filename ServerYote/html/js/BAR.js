
var root = yote_worker.fetch_root();

// will set up a posting list if there is none
root.get( 'postinglist', function() { return root.newobj( ['_list','postinglist' ] ); } );

