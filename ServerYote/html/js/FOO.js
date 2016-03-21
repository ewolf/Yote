// for worker to load. Whee weee weee

yote_worker.addToStamps( 'posting', function( obj ) {

    // postings are only interesting to save if they are annotated
    obj._save_me_p = function() {
        return this.get('name') || this.get('annotation');
    }

}, [] );

yote_worker.addToStamps( 'postinglist', function( obj ) {

    // a postinglist only saves 'interesting' postings, 
    // namely those with annontations
    obj._save_me_p = function() {
        var ta = this.toArray();
        for( var i=0,len=ta.length; i<len; i++ ) {
            if( ta[i]._save_me_p() ) {
                return true;
            }
        }
        return false;
    };
    obj._save_data = function() {
        var saves = [];
        var ta = this.toArray();
        for( var i=0,len=ta.length; i<len; i++ ) {
            if( ta[i]._save_me_p() ) {
                saves.push( ta[i].id );
            }
        }
        return saves;
    };

    obj.on_load = function() {
        var posts = this.toArray();
        var pidmap = {};
        for( var i=0, len=posts.length; i<len; i++ ) {
            pidmap[posts[i].get( 'PostingID' )] = posts[i];
        }
        this.pidmap = pidmap;
    }; //postingMaster.onload

    obj.lookup = function( pid ) {
        var pidmap = this.pidmap;
        if( pidmap[ pid ] ) {
            return pidmap[ pid ];
        }
        var posting = root.newobj( ['_list_container','posting'], { PostingID : pid } );
        this.push( posting );
        
        return posting;
    }; //postingMaster.lookup


}, ['lookup'] ); //postinglist



