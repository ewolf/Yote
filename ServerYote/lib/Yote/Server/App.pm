package Yote::Server::App;

use Yote::Server;

use Digest::MD5 qw( md5_hex );

use base qw( Yote::ServerApp Yote::Server::ListContainer );

sub _init {
    my $self = shift;
}

sub _acct_class { "Yote::ServerObj" }

sub create_account {
    my( $self, $un, $pw ) = @_;
    my $accts = $self->get__accts;
    my $acct = $self->{STORE}->newobj( { user => $un }, $self->_acct_class );
    $acct->set_password_hash( crypt( $pw, length( $pw ) . md5_hex($acct->{ID} ) )  );
                                       
    if( $acct->{$un} ) {
        die "Unable to create account";
    }

    # TODO - create an email infrastructure for account validation
    
    $acct->{$un} = $acct;
    $acct;
} #create_account

sub login {
    my( $self, $un, $pw ) = @_;

    # returns account, cookie. only way to get account object
    my $acct = $self->get__accts->{$un};

    # doing it like this so a failed attempt has about the same amount of time
    # as an attempt against a nonexistant account. maybe random microsleep?
    my $pwh = crypt( $pw, length( $pw ) . md5_hex($acct ? $acct->{ID} : $self->{ID} ) );
    if( $acct && $pwh eq $acct->get_password_hash ) {
        # this and Yote::ServerRoot::fetch_app are the only ways to expose the account obj
        # to the UI. If the UI calls for an acct object it wasn't exposed to, Yote::Server
        # won't allow it. fetch_app only calls it if the correct cookie token is passed in
        $self->{TOKEN}->set__acct( $self );
        return $acct;
    }
    die "Incorrect login";
} #login

1;
