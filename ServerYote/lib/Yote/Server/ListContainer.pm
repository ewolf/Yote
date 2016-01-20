package Yote::Server::ListContainer;

#
# Caveats. Be careful
#   * with gather/gather_all
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
sub _allowedUpdates { [] } #override returning a list of allowed updates

sub _lists { {} }  # override with list-name -> class


# new item added to this object
sub _on_add { my($self,$listName,$obj,$moreArgs) =@_; } 

# what to run when added to something
sub _when_added { my($self,$toObj,$listName,$moreArgs) =@_;}

sub _gather {}

sub _init {
    my $self = shift;
    my $listhash = $self->_lists;
    for my $list (keys %$listhash) {
        $self->set( $list, [] );
    }
}

#
# for the <options val="value">title</option> of <select> controls
# return list ref of valid choices for the given field
# the choices can be value/title pairs or scalars. If scalars, it assumes
# the value and title are the same. For scalar ListContainer objects, it
# uses the name as the key
#
sub choices { 
    my( $self, $field ) = @_;
    my $l = $self->get( $field );
    if( ref( $l ) eq 'ARRAY' ) {
        return @$l;
    }
    return ();
}
sub calculate {}  #override

# --^^^ override -------

sub _valid_choices {
    my( $self, $field ) = @_;
    my( @choices ) = $self->choices( $field );
    if( @choices) {
        return { map { $_ => 1 } map { ref $_ eq 'ARRAY' ? $_->[0]  : $_ } @choices };
    }
}

sub __allowedUpdates {
    map { $_ => 1 } @{shift->_allowedUpdates()};
}

sub update {
    my( $self, $updates ) = @_;
    my %allowed = $self->__allowedUpdates;
    for my $fld (keys %$updates) {
        die "Cant update '$fld' in ".ref($self) unless $allowed{$fld};
        my $val = $updates->{$fld};
        my $valid_choices = $self->_valid_choices($fld);
        if( $valid_choices && ! $valid_choices->{$val} ) {
            if( $valid_choices->{undef} ) {
                $val = undef;
            } else {
                die "Cant update '$fld' to $val in " . ref($self);
            }
        }
        $self->set( $fld, $val )
    }
    $self->calculate;
} #update

sub add_entry {
    my( $self, $args ) = @_;
    
    my($listName, $obj, $itemArgs, $parentArgs ) = @$args{'listName', 'item', 'itemArgs', 'parentArgs'};
    
    my $class = $self->_lists->{$listName};
    
    die "Unknown list '$listName' in ".ref($self) unless $class;
    my $list = $self->get( $listName, [] );
    $obj //= $self->{STORE}->newobj( {
        parent => $self,
        name   => $listName.' '.(1 + @$list),
                                        },$class  );
    $obj->_when_added( $self, $listName, $itemArgs );
    $self->_on_add( $listName, $obj, $parentArgs );
    push @$list, $obj;
    $self->select_current( $listName, $obj );
    $obj, $obj->gather_all;
} #add_entry

sub select_current {
    my( $self, $listName, $item ) = @_;
    die "Unknown list '$listName' in ".ref($self) unless $self->_lists->{$listName};
    $self->set( "current_$listName", $item );
    $item;
} #select_current

sub gather {
    my $self = shift;
    my $listhash = $self->_lists;
    my @res;
    for my $list (keys %$listhash) {
        my $l = $self->get( $list, [] );
        push @res, $l, @$l;
    }
    @res, $self->_gather;
} #gather

sub gather_all {
    my $self = shift;
    my $listhash = $self->_lists;
    my @res;
    for my $list (keys %$listhash) {
        my $l = $self->get( $list, [] );
        push @res, $l, (map { $_, $_->gather_all } @$l);
    }
    @res, $self->_gather;
} #gather_all

sub remove_entry {
    my( $self, $item, $from ) = @_;
    die "Unknown list '$from' in ".ref($self) unless $self->_lists->{$from};
    my $list = $self->get($from);
    for( my $i=0; $i<@$list; $i++ ) {
        if( $list->[$i] == $item ) {
            splice @$list, $i, 1;
            if( @$list ) {
                $i-- if $i > $#$list;
                $self->select_current( $from, $list->[$i] );
                return $item;
            } else {
                $self->select_current( $from, undef );
            }
        }
    }
} #remove_entry

# TODO - implement a copy?
1;

__END__
