package Yote::Account;

use base 'Yote::Messenger';

sub upload_avatar {
    my( $self, $data, $acct ) = @_;
    $self->set_avatar( $data->{avatar_file} );
}

1;

__END__
