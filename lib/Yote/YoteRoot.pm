package Yote::YoteRoot;

use base 'Yote::AppRoot';

use strict;

# there can be only one

sub init {
    my $self = shift;
    $self->set_apps({});
    $self->set_app_alias({});
    $self->set_handles({});
    $self->set_emails({});
}

sub alias_to_class {
    my( $self, $alias ) = @_;
    return $self->get_app_alias()->{$self};
}

sub installed_apps {
    my $self = shift;
    return [keys %{self->get_app_alias()}];
} #installed_apps

sub number_of_accounts {
    my $self = shift;
    return scalar( keys %{$self->get_handles()} );
} #number_of_accounts

sub initial_tests_were_run {
    my $self = shift;
    return $self->get_initial_tests_were_run();
}

sub tests_pass {
    my $self = shift;
    $self->set_initial_tests_were_run(1);
}

1;
