package Yote::Root;

use parent Yote::Obj;

sub fetch_root {
    my $root = Yote::ObjProvider::fetch( Yote::ObjProvider::first_id() );
    unless( $root ) {
        $root = new Yote::Root();
        Yote::ObjProvider::stow( $root );
    }
    return $root;
}

1;
