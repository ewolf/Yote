package Yote::CronEntry;

use strict;
use warnings;

use base 'Yote::Obj';

sub _load {
    my $self = shift;
    $self->get_name( 'cron entry' );
    $self->get_enabled( 1 );
    $self->get_script( '' );
    $self->get_repeats( [] );
    $self->get_scheduled_times( [] );
    $self->get_next_time( 0 );
    $self->get_last_run( 0 );
}

sub update {
    my( $self, $data, $acct ) = @_;
    die "Access Error" unless $acct->is_root();
    
    $self->_update( $data, 'name', 'enabled', 'script' );
    return;
} #update

1;

__END__

=head1 NAME

Yote::CronEntry

=head1 DESCRIPTION

This contains a name, a script and information on how to repeat and schedule the script to run.

=head1 INIT METHODS

=over 4

=item update

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
