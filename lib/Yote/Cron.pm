package Yote::Cron;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';

use DateTime;

use base 'Yote::Obj';

#
# This should be rewritten.
# 

# ------------------------------------------------------------------------------------------
#      * INITIALIZATION *
# ------------------------------------------------------------------------------------------


sub _init {
    my $self = shift;
    $self->set__crond( {} );
} #_init



# ------------------------------------------------------------------------------------------
#      * UTILITY Methods *
# ------------------------------------------------------------------------------------------

#
# maintain a list of items that are pending.
#
sub _check {
    my( $self ) = @_;
    my $data = $self->get__crond();
    $self->{now} ||= DateTime->now();
    my( $min, $hr ) = ( $self->{now}->minute, $self->{now}->hour );

    $self->__activate( $data->{$min}{'*'} ); # every $min past an hour
    $self->__activate( $data->{$min}{'+'} ); # every $min minutes
    $self->__activate( $data->{$min}{$hr} ); # specific time
    $self->__activate( $data->{'*'}{$hr}  ); # specific hour

    return "";
} #_check

# ------------------------------------------------------------------------------------------
#      * PUBLIC API Methods *
# ------------------------------------------------------------------------------------------

sub add {
    my( $self, $data, $acct ) = @_;
    die "Incorrect permissions" unless $acct->__is_root();
    push( @{$self->get__crond()->{ $data->{minute} }{ $data->{hour} }}, [ $data->{obj}->{ID}, $data->{method} ] );
    return "Added";
}

sub remove {
    my( $self, $data, $acct ) = @_;
    die "Incorrect permissions" unless $acct->__is_root();

    my $crond = $self->get__crond();
    if( $crond->{ $data->{minute} }{ $data->{hour} } ) {
	my $pairs = $crond->{ $data->{minute} }{ $data->{hour} };
	for( my $i=0; $i<@$pairs; ++$i ) {
	    if( $pairs->[$i][0] == $data->{obj}->{ID} && $pairs->[$i][1] eq $data->{method} ) {
		splice( @$pairs, $i, 1 );
		return "Found and removed";
	    }
	}
    }
    return "Not Found";
} #remove

sub show {
    my( $self, $data, $acct ) = @_;
    die "Incorrect permissions" unless $acct->__is_root();
    my( @does );
    my $crond = $self->get__crond();
    for my $min ( keys %$crond ) {
	for my $hr ( keys %{$crond->{$min}} ) {
	    my $pairs = $crond->{$min}{$hr};
	    for my $pair (@$pairs) {
		push( @does, "$min $hr ".join( " ", @$pair ) );
	    }
	}
    }
    return \@does;
} #show


# ------------------------------------------------------------------------------------------
#      * Private Methods *
# ------------------------------------------------------------------------------------------

#builds the next items that are in the next 10 mins of the current time.
sub __build_cron_list {
    
} #__build_cron_list

sub __activate {
    my( $self, $items ) = @_;
    ### CRON activate with $items
    if( $items && @$items ) {
	for my $item (@$items) {
	    my( $obj_id, $method ) = @$item;
	    my $obj = $self->_fetch( $obj_id );
	    eval {
		$obj->$method();
	    };
	}
    }
} #__activate


1;

__END__

=head1 NAME

Yote::Cron

=head1 SYNOPSIS

The Yote::Cron, while it works as design, has a poor enough design that I'm yanking it from 
production.

=head1 DESCRIPTION

The Yote::Cron is set up on the yote system and runs every minute, checking if it should run 
any method that is attached to a yote object. It is a limited version of a cron system, as it
for now only registers methods with minutes and hours.

The Yote::Cron's public methods can only be called by an account with the __is_root flag set.

=head1 PUBLIC METHODS

=over 4

=item add

Takes a hash that has hour, minute, obj, method.

=item remove

Removes the entry the corresopnds with the input, which is a hash ref containing the fields minute, hour, obj, method

=item show

Returns a list of all cron entries as strings in the format "min hour obj-id menthodname"

=back

=head1 UTIL METHODS

=over 4

=item _check

Performs the cron check, running the method given on the object.

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut


