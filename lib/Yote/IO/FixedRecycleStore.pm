package Yote::IO::FixedRecycleStore;

use strict;

use Yote::IO::FixedStore;
use parent 'Yote::IO::FixedStore';

sub new {
    my( $pkg, $template, $filename, $size ) = @_;
    my $self = $pkg->SUPER::new( $template, $filename, $size );
    $self->{RECYCLER} = new Yote::IO::FixedStore( "L", "${filename}.recycle" );
    return $self;
} #new

sub delete {
    my( $self, $idx ) = @_;
    $self->{RECYCLER}->push( $idx );
}

sub next_id {
    my $self = shift;
    my $recycled_id = $self->{RECYCLER}->pop;
    print STDERR Data::Dumper->Dump([$recycled_id,$self->SUPER::next_id,"COOOOOO"]);
    return $recycled_id ? $recycled_id->[0] : $self->SUPER::next_id;
}

1;

__END__
