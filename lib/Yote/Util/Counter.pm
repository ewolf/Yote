package Yote::Util::Counter;

use strict;

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

sub pages {
    my( $self,$data, $account, $env ) = @_;
    return [ keys %{$self->get__counts()} ];
}

sub count {
    my( $self,$data, $account, $env ) = @_;
    return $self->get__counts()->{$data};    
}

1;

__END__
