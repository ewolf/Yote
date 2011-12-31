package GServ::SE::Ship;

use strict;
use base 'GServ::Obj';


sub kill {
    my $self = shift;
    $self->set_dead( 1 );
    my $carried = $self->get_carried();
    my( @loaded );
    for my $item (@$carried) {
        my( @l ) = $item->kill();
        push( @loaded, @l );
    }
    return @loaded;
} #kill

sub replenish {
    my $self = shift;

    $self->set_remaining_targets( $self->get_prototype('targets') );
    $self->set_remaining_beams( $self->get_prototype('beams') );
    $self->set_remaining_move( $self->get_prototype('jumps') );

    my $need_to_repair = $self->get_prototype('defenese') > $self->get_health() ? $self->get_prototype('defenese') - $self->get_health() : 0;
    if( $need_to_repair > $self->get_prototype('damage_control') ) {
	$need_to_repair = $self->get_prototype('damage_control');
    }
    if( $need_to_repair && $self->get_prototype('damage_control') ) {
	my $report = { target => $self, action => 'damage control', amount => $need_to_repair,
		       msg => $self->get_owner()->get_name()." ".$self->get_name()." self repaired $need_to_repair damage" };
	$self->get_owner()->message( $report );
	$self->set_health( $self->get_health() + $self->get_prototype('damage_control') );
	if( $self->get_health() > $self->get_prototype( 'defense' ) ) {
	    $self->set_health( $self->get_prototype( 'defense') );
	}
    }
} #replenish

sub set_prototype {
    my( $self, $prot ) = @_;
    $self->set('prototype',$prot);
    $self->set_health( $prot->get_defense() );
    $self->set_free_rack( $prot->get_racksize() );
    $self->set_remaining_move( $prot->get_jumps() );
    $self->set_remaining_targets( $prot->get_targets() );
    return undef;
}

sub get_prototype {
    my( $self, $field ) = @_;
    my $p = $self->get( 'prototype' );

    unless($p){
	$p = $self->get_owner()->get_game()->get_flavor()->get_prototypes()->{4};
	$self->set('prototype',$p);
    }
    return $p->get($field) if $field;
    return $p;
}

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut
