package Yote::Util::Counter;

use base 'Yote::AppRoot';

sub _init {
    my $self = shift;
    $self->set__counts( {} );
}

sub increment {
    my( $self, $data, $account, $env ) = @_;
    my $ip = $env->{ REMOTE_ADDR };
    my $count = $self->get__counts()->{$data} + 1; 
    $self->get__counts()->{$data} = $count; 
    return $count;
}

1;

__END__
