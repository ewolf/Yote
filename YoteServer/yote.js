
var res = ''; // persists, so ya.
// yote objects can be stored here, and interpreting
// etc can be done here, the get & stuff
var reqListener = function() {
    res = JSON.parse( this.responseText );
}

var contact = function() {
    var oReq = new XMLHttpRequest();
    oReq.addEventListener("load", reqListener);
    oReq.open("POST", "http://localhost:8881/_/test", false);
    oReq.send("x=vFOO&y=vBar");
    return res;
};
self.contact = contact;
