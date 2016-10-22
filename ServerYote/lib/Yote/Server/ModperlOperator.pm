package Yote::Server::ModperlOperator;

use strict;
no strict 'refs';

use Apache2::Cookie;
use Apache2::Const qw(:common);
use Data::Dumper;
use Text::Xslate qw(mark_raw);

use Yote::Server;

sub new {
    my( $pkg, %options ) = @_;

    #
    # Setup the yote part of this
    #
    my $yote_root_dir = '/opt/yote';
    eval {
        require Yote::ConfigData;
        $yote_root_dir = Yote::ConfigData->config( 'yote_root' );
    };
    unshift @INC, "$yote_root_dir/lib";
    my $yote_options = Yote::Server::load_options( $yote_root_dir );
    my $server  = new Yote::Server( $yote_options );
    my $store   = $server->store;
    my $root    = $store->fetch_server_root;


    bless {
        apps          => $options{apps},
        template_path => $options{template_path},
        root          => $root,
        tx            => new Text::Xslate,
    }, $pkg;

} #new

sub handle_request {
    my( $self, $req ) = @_;

    my( $app_path, @path  ) = grep { $_ } split '/', $req->uri;

    my $jar = Apache2::Cookie::Jar->new($req);
    my $token_cookie = $jar->cookies("token");
    my $root = $self->{root};
    my $appinfo = $self->{apps}{$app_path};

    my( $app, $login, $session );
    $session = $root ? $root->fetch_session( $token_cookie ? $token_cookie->value : 0 ) : undef;
    unless( $token_cookie && $token_cookie->value eq $session->get__token ) {
        my $cookie_path = $appinfo ? $appinfo->{cookie_path} : '/';
        $token_cookie = Apache2::Cookie->new( $req,
                                              -name => "token",
                                              -path => $cookie_path,
                                              -value => $session->get__token );
        
       $token_cookie->bake( $req );
    }
    my $template = 'main';
    if( $appinfo && $root ) {
        $root->{SESSION} = $session;
        ( $app, $login ) = $root->fetch_app( $appinfo->{app_name} );
        $app->{SESSION}  = $session;
        if( $login ) {
            $login->{SESSION} = $session;
        }
        $template = "$app_path/main";
    }

    my $state = {
        app_info => $appinfo,
        app_path => $app_path,
        app      => $app,
        login    => $login,
        op       => $self,
        req      => $req,
        session  => $session,
        path     => \@path,
        template => $template,
    };

    eval {
        $self->_check_actions( $state );
        $self->make_page( $state );
        $root->{STORE}->stow_all;
    };
    if( $@ ) {
        print STDERR Data::Dumper->Dump([$@,"ERRY"]);
    }

} #handle_request

sub tmpl {
    my( $self, @path ) = @_;
    join( '/', $self->{template_path}, @path ).'.tx';
}

sub _check_actions {
    my( $self, $state );
    # login check, et al go here
}

sub make_page {
    my( $self, $state ) = @_;

    my $req      = $state->{req};
    my $template = $state->{template};

    my $html = $self->{tx}->render( $self->tmpl( $template ), $state );

    $req->print( mark_raw($html) );

    return OK;
} #make_page


1;

__END__

=head1 NAME

Yote::Server::ModperlOperator - marry the yote server to xslate templates



=cut
