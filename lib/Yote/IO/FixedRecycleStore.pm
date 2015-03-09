package Yote::IO::FixedRecycleStore;

use strict;

use Yote::IO::FixedStore;
use parent 'Yote::IO::FixedStore';

sub new {
    my( $pkg, $template, $filename, $size ) = @_;
    my $self = $pkg->SUPER::new( $template, $filename, $size );
    $self->{RECYCLER} = new Yote::IO::FixedStore( "L", "${filename}.recycle" );
    return bless $self, $pkg;
} #new

sub delete {
    my( $self, $idx, $purge ) = @_;
    $self->{RECYCLER}->push( $idx );
    if( $purge ) {
        $self->put_record( $idx, [] );
    }
} #delete

sub get_recycled_ids {
    my $self = shift;
    my $R = $self->{RECYCLER};
    my $max = $R->entries;
    my @ids;
    for( 1 .. $max ) {
        push @ids, @{ $R->get_record( $_ ) };
    }
    return \@ids;
} #get_recycled_ids

sub next_id {
    my $self = shift;
    my $recycled_id = $self->{RECYCLER}->pop;
    return $recycled_id ? $recycled_id->[0] : $self->SUPER::next_id;
} #next_id

1;

__END__
