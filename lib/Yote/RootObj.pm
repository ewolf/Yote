package Yote::RootObj;

use strict;
use warnings;

use base 'Yote::Obj';

sub count {
    my( $self, $args, $account, $env ) = @_;
    die "Access Error" unless $account->is_root();
    return $self->SUPER::count( $args, $account, $env );
}


sub paginate {
    my( $self, $args, $account, $env ) = @_;
    die "Access Error" unless $account->is_root();
    return $self->SUPER::paginate( $args, $account, $env );
}

sub update {
    my( $self, $args, $account, $env ) = @_;
    die "Access Error" unless $account->is_root();
    return $self->SUPER::update( $args, $account, $env );
}

1;

__END__
