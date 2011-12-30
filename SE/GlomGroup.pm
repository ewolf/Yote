package GServ::SE::GlomGroup;

use strict;

sub new {
    my $ref = shift;
    my $class = ref( $ref ) || $ref;
    my $self = {};
    return bless $self, $class;
} #new

sub glom {
    my( $self, $group ) = @_;
    $self->connect( $group );
    $self->{groups}{$group} = $group;
} #glom

sub connect {
    my( $self, $group ) = @_;

    my @groups = grep { $group ne $_ && $_->get_outbound_count() > 0 } values( %{$self->{groups}} );
    if( @groups ) {
        my( @selector );
        for my $g (@groups) {
	    next if $group->{is_empire} && $g->{is_empire};
            for(1..$g->get_outbound_count()) {
                push @selector, $g;
            }
        }
        my $connector_group = $selector[int(rand(scalar @selector))];
        $connector_group->link_group( $group );
    }
    $self->{groups}{$group} = $group;
    return undef;
} #connect

sub get_unlinked_groups {
    my $self = shift;
	my $ul = 0;
    for my $g (values %{$self->{groups}||{}}) {
        ++$ul if $g->get_outbound_count();
    }
    return $ul;
} #get_unlinked_groups

sub set_sectors {
    my( $self, $sectors ) = @_;
    $self->{sectors} = $sectors;
    
    for my $s (@$sectors) {
        my $links = $s->get_outbound_links();
        for( 1..$links ) {
            $self->{outbound}{$s->{ID}} = $s;
        }
    }
} #set_sectors

sub get_outbound_count {
    my $self = shift;
    return scalar( keys %{$self->{outbound}} );
}

sub link_group {
    my $self = shift;
    my $group = shift;
    die "no free links to connect in link_group" unless $group->get_outbound_count() && $self->get_outbound_count();
    my( @pick );
    for my $g (values %{$self->{groups}}) {
        for(1..$g->get_outbound_count()) {
            push( @pick, $g );
        }
    }
    my $pick = $pick[int(rand(scalar @pick))];

    $pick->link_group( $group );
} #link_group

sub get_sector_count {
    my $self = shift;
    return scalar( @{$self->{sectors}} );
}

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut
