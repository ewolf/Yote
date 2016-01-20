package Samp::Scenario;

sub _init {
    my $self = shift;
    $self->set_employees([]);
    $self->set_overhead(0);
    $self->set_product_lines([]);
}

1;

__END__
