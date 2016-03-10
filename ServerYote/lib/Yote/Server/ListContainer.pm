 package Yote::Server::ListContainer;

#
# Caveats. Be careful
#   * with gather
#   * when using js clearCache
#   * about asyn with  yote object methods
#   * about 'use Foo' for ListContainer list objects
#


use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;
use base 'Yote::ServerObj';

# --vvv override -------
sub _allowedUpdates { qw(name notes) } #override returning a list of allowed updates

sub _lists { {} }  # override with list-name -> class

sub _gather {}  # override with extra stuff to send across

sub _init {
    my $self = shift;
    my $listhash = $self->_lists;
    for my $list (keys %$listhash) {
        $self->set( $list, [] );
    }
}

sub calculate {}  #override

# --^^^ override -------

sub _valid_choice { return 1; }

sub __allowedUpdates {
    my $self = shift;
    $self->{__ALLOWED} //= { map { $_ => 1 } ($self->_allowedUpdates) };
}

sub update {
    my( $self, $updates ) = @_;
    my %allowed = %{$self->__allowedUpdates};
    for my $fld (keys %$updates) {
        die "Cant update '$fld' in ".ref($self) unless $allowed{$fld};
        my $val = $updates->{$fld};
        die "Cant update '$fld' to $val in " . ref($self) 
            unless $self->_valid_choice($fld,$val);
        $self->set( $fld, $val )
    }
    $self->calculate( 'update' );
} #update

sub add_entry {
    my( $self, $listName, $obj ) = @_;
    
    my $class = $self->_lists->{$listName};
    
    die "Unknown list '$listName' in ".ref($self) unless $class;
    die "Cannot add this choice to list $listName in ".ref($self) 
        unless $self->_valid_choice( $listName, $obj );

    my $list = $self->get( $listName, [] );
    $obj //= $self->{STORE}->newobj( {
        parent => $self,
        name   => $listName.' '.(1 + @$list),
                                        },$class  );
    $obj->get_parent( $self );

    push @$list, $obj;
    $obj->calculate( 'added_to_list', $listName, $self );
    $self->calculate( 'new_entry', $listName, $obj );
    $obj, $obj->gather;
} #add_entry

sub gather {
    my $self = shift;
    my $seen = shift || {};
    my $listhash = $self->_lists;
    my @res;
    for my $list (keys %$listhash) {
        my $l = $self->get( $list, [] );
        push @res, $l, (map { $_, $_->gather($seen) } grep { ref($_) && ! $seen->{$_->{ID}}++ } @$l);
    }
    @res, $self->_gather;
} #gather

sub remove_entry {  #TODO - paramertize this like add_entry does
    my( $self, $item, $from, $moreArgs ) = @_;
    die "Unknown list '$from' in ".ref($self) unless $self->_lists->{$from};
    my $list = $self->get($from);
    for( my $i=0; $i<@$list; $i++ ) {
        if( $list->[$i] == $item ) {
            splice @$list, $i, 1;
        }
    }
    $self->calculate( 'removed_entry', $from );
    return $item;
} #remove_entry

# TODO - implement a copy?
1;

__END__
