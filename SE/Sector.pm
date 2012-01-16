package Yote::SE::Sector;

use strict;

use Yote::Obj;

use base 'Yote::Obj';

sub link_sectors {
    my( $self, $other ) = @_;
    my $Alinks = $self->get_links({});
    my $Blinks = $other->get_links({});
    $Alinks->{$other->{ID}} = $other;
    $Blinks->{$self->{ID}} = $self;
    return undef;
}

# takes an id of a sectors and returns true if the two link together.
sub valid_link {
    my( $self, $id ) = @_;
    my $links = $self->get_links();
    if( $links->{$id} ) {
	my $olinks = $links->{$id}->get_links();
	return $olinks->{$self->{ID}} && $id == $links->{$id}{ID};
    }
    return 0;
}

sub valid_links {
    my $self = shift;
    my $seen = shift;
    my $links = $self->get_links();

    for my $key (keys %$links) {
	next if $seen->{$key};
	$seen->{$key} = 1;
	return 0 unless $self->valid_link( $key );
	return 0 unless $links->{$key}->valid_links( $seen );
    }
    return 1;
}

1;

__END__


=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

=cut
