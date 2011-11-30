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
				     1, false );
	    },
	    message:function( cmd, data, wait, async, callback ) {
		var res;
		$.jsonp({
		    url: this.url,
		    data:{
			m: $.base64.encode(JSON.stringify(
			    {
				a:this.app,
				c:cmd,
				d:data,
				t:this.token,
				w:wait
			    } ))
		    },
		    callbackParameter: "callback",
		    dataFilter:function(json) { return json; },
		    success:function(json,s) { res = json;alert(res) },
		    error:function(x,s) { alert("error "+s ) }
		});
		alert(res);
		return res;
		
//Jerry from Michigan calling regards to Drew & Bakery 989.671.1942
/*
		var ret;
		async = async == null ? true : async;

		$.ajax({
		    async:false,
		    success:function(data) {
			alert('status :');
		    },
		    error:function(jqXHR, textStatus, errorThrown) {
			alert('errstatus :'+$.dump(textStatus)+','+$.dump(errorThrown));
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
		    dataType:'json',
		    type:'POST',
		    url:this.url
		});

		return ret;
*/
	    }
	};
    }
};
