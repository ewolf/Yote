package Yote::Server::ModperlOperator;

use strict;
no strict 'refs';

use Apache2::Cookie;
use Apache2::Const qw(:common);
use Data::Dumper;
use Text::Xslate qw(mark_raw);

use Yote::Server;

sub new {
    my( $pkg, $r, %options ) = @_;

    my $jar = Apache2::Cookie::Jar->new($r);
    my $token_cookie = $jar->cookies("token");
    my $token = $token_cookie ? $token_cookie->value : 0;
    my( @path ) = grep { $_ } split '/', $r->uri;

    bless {
        r      => $r,
        cookie_path => $options{cookie_path},
        template_path => $options{template_path},
        app_name    => $options{app_name},
        main_template => $options{main_template},
        token  => $token,
        path   => \@path,
    }, $pkg;
    
} #new

sub path {
    shift->{path};
}

sub req {
    shift->{r}
}

sub _load_app {
    my( $self, $appname ) = @_;

    eval('use Yote::ConfigData');
    my $yote_root_dir = $@ ? '/opt/yote' : Yote::ConfigData->config( 'yote_root' );
    unshift @INC, "$yote_root_dir/lib";

    my $options = Yote::Server::load_options( $yote_root_dir );
    my $server  = new Yote::Server( $options );
    my $store   = $server->store;
    my $root    = $store->fetch_server_root;
    
    my $session = $root->_fetch_session( $self->{token} ) || $self->_init_session;
    $self->{session} = $session;
    $root->{SESSION} = $session; # _fetch_session doens't attach the session to the root oddly. TODO - look into this.
    
    $self->{root}    = $root;
    $self->{store}   = $store;
    
    my( $app, $login ) = $root->fetch_app( $appname );
    if( $app ) {
        $app->{SESSION} = $session;
        $self->{app}   = $app;
        $self->{login} = $login;
        if( $login ) {
            $login->{SESSION} = $session;
        }
        return $app;
    }
    # oh, no app here. That's not good. TODO - figure out what to do.
} #_load_app

sub _init_session {
    my $self = shift;
    my($root, $token) = $self->{root}->init_root;
    $self->{token} = $token;
    my $token_cookie = Apache2::Cookie->new( $self->{r},
                                             -name => "token",
                                             -path => "/$self->{cookie_path}",
                                             -value => $self->{token} );
    $token_cookie->bake( $self->{r} );
    $root->{SESSION};
}

sub haslogin {
    defined shift->{login};
}

sub _err {
    my( $self, $err ) = @_;
    $err //= $@;
    if( ref $err ) {
        $self->{last_err} = $err->{err};
        return $err->{err};
    } elsif( $err ) {
        die $err;
    }
} #_err

sub lasterr {
    shift->{last_err};
}

sub logout {
    my $self = shift;
    my $token_cookie = Apache2::Cookie->new( $self->{r},
                                             -name => "token",
                                             -path => "/$self->{cookie_path}",
                                             -value => 0 );
    $token_cookie->bake( $self->{r} );
    delete $self->{token};
    delete $self->{login};

    #re-establish a new session
    $self->_init_session;
    '';
} #logout

sub login {
    my $self = shift;
    return $self->{login} if $self->{login};
    my $r = $self->{r};
    my( $un, $pw ) = ( $r->param('un'), $r->param('pw') );
    my $login;
    if( $un && $pw ) {
        $login = $self->{app}->login( $un, $pw );
        $login->{SESSION} = $self->{session};
        $self->{login} = $login;
    }
    $login;
} #login

sub tmpl {
    my( $self, $tname ) = @_;
    "$self->{template_path}/$tname.tx";
} #tmpl

sub make_page {
    my $self = shift;

    my $tx = new Text::Xslate;
    $self->_load_app($self->{app_name});
    eval {
        $self->login;
    };
    $self->_err;
    my( @path ) = @{$self->{path}};
    $self->{r}->print( $tx->render( $self->tmpl($self->{main_template}), { 
        op => $self, } ) );

    $self->{store}->stow_all;
    
    return $self->{rv};
} #make_page

1;

__END__

=head1 NAME

Yote::Server::ModperlOperator - marry the yote server to xslate templates



=cut
