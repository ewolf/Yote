package Samp::Component;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;
use base 'Yote::ServerObj';

# --vvv override -------
sub allowedUpdates { [] } #override returning a list of allowed updates

sub lists { {} }  # override with list-name -> class

sub calculate {}  #override

# --^^^ override -------

sub _allowedUpdates {
    map { $_ => 1 } @{shift->allowedUpdates()};
}
sub _init {
    my $self = shift;
    my $listhash = $self->lists;
    for my $list (keys %$listhash) {
        $self->set( $list, [] );
    }
}

sub update {
    my( $self, $updates ) = @_;
    my %allowed = $self->_allowedUpdates;
    for my $fld (keys %$updates) {
        die "Cant update '$fld'" unless $allowed{$fld};
        my $s = "set_$fld";
        $self->$s( $updates->{$fld} );
    }
    $self->calculate;
}

sub add_entry {
    my( $self, $list ) = @_;

    my $class = $self->lists->{$list};
    die "Unknown list '$list'" unless $class;
    my $obj = $self->{STORE}->newobj( {
        parent => $self,
                                      },$class  );
    my $add = "add_to_$list";
    $self->$add( $obj );
    $obj;       
}

sub gather {
    my $self = shift;
    my $listhash = $self->lists;
    my @res;
    for my $list (keys %$listhash) {
        my $l = $self->get( $list, [] );
        push @res, $l, (map { $_, $_->gather } @$l);
    }
    @res;
} #gather

sub remove_entry {
    my( $self, $item, $from ) = @_;
    die "Unknown list '$from'" unless $self->lists->{$from};
    my $rem = "remove_from_$from";
    $self->$rem($item);
}

# TODO - implement a copy?
1;

__END__
