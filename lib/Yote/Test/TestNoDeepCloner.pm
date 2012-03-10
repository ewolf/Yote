package Yote::Test::TestNoDeepCloner;

use base 'Yote::Obj';

sub _on_load {
    my $self = shift;
    $self->{NO_DEEP_CLONE} = 1;
}

1;

__END__
