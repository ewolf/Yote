package Yote::SE::Group;

use strict;

sub new {
    my $ref = shift;
    my $class = ref( $ref ) || $ref;
    my $self = {};
    return bless $self, $class;
} #new

sub set_sectors {
    my( $self, $sectors ) = @_;
    $self->{sectors} = $sectors;
    
    for my $s (@$sectors) {
	my $link_count = $s->get_outbound_links();
        $self->{outbound}{$s->{ID}} = $link_count if $link_count;
    }
} #set_sectors

sub get_outbound_count {
    my $self = shift;
    my $count = 0;
    for my $o (keys %{$self->{outbound}}) {
        $count += $self->{outbound}{$o};
    }
    return $count;
}

sub link_group {
    my $self = shift;
    my $group = shift;

    die "no free links to connect in link_group" unless $group->get_outbound_count() && $self->get_outbound_count();

    my( @selector ) = map { Yote::ObjProvider::fetch( $_ ) } grep { $self->{outbound}{$_} > 0 } keys %{$self->{outbound}};
    my $self_sector = $selector[int(rand(scalar @selector))];

    my( @selector ) = map { Yote::ObjProvider::fetch( $_ ) } grep { $group->{outbound}{$_} > 0 } keys %{$group->{outbound}};
    my $group_sector = $selector[int(rand(scalar @selector))];
    if( $group_sector ) {
        $self_sector->link_sectors( $group_sector );            
        --$self->{outbound}{$self_sector->{ID}};
        delete $self->{outbound}{$self_sector->{ID}} if $self->{outbound}{$self_sector->{ID}} == 0;
        --$group->{outbound}{$group_sector->{ID}};
        delete $group->{outbound}{$group_sector->{ID}} if $group->{outbound}{$group_sector->{ID}} == 0;
    }
    return undef;
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
