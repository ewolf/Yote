jQuery.gServ = {
    make_app:function(target_app,target_url){
	return {
	    app:target_app,
	    token:null,
	    err:null,
	    url:target_url,
	    login:function( un, pw ) {
		var m = this.message( 'login',
				 {
				     h:un,
				     p:pw
				 },
				 1);
		this.token = m.t;
		return m.msg == 'logged in';
	    },
	    create_account:function( un, pw, em ) {
		return this.message( 'create_account',
				{
				    h:un,
				    p:pw,
				    e:em
				},
				     1, false ).msg == 'created account';
	    },
	    message:function( cmd, data, wait, async, callback ) {
		var ret;
		async = async == null ? true : async;
		$.ajax({
		    async:false,
		    complete:function(jqXHR,textStatus) {
			alert('status :'+textStatus);
			alert(jqXHR);
		    },
		    data:{ m:$.base64.encode(JSON.stringify(
			{
			    a:this.app,
			    c:cmd,
			    d:data,
			    t:this.token,
			    w:wait
			} ) )
			 }, 
		    dataType:'jsonp',
		    type:'POST',
		    url:this.url
		});
		alert( 'returning ret' );
		return ret;
	    }
	};
    }
};
