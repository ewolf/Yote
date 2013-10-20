package Yote::Cron;

#######################################################################################################
# This module is not meant to be used directly. It is activated automatically as part of the service. #
#######################################################################################################


use strict;
use warnings;
no warnings 'uninitialized';

use vars qw($VERSION);
$VERSION = '0.014';

use DateTime;

use base 'Yote::RootObj';

##################
# Public Methods #
##################

sub add_entry {
    my( $self, $entry, $acct ) = @_;
    $self->add_to_entries( $entry );
    $self->_update_entry( $entry );
    return $entry;
} #add_entry

sub entries {
    my $self = shift;
    my $now_running = _time();
    my( $e ) = @{ $self->get_entries() };
    return [grep { $_->get_enabled() && $_->get_next_time() && $now_running >= $_->get_next_time() } @{ $self->get_entries() }];
} #entries


sub mark_done {
    my( $self, $entry, $acct ) = @_;
    die "Access Error" unless $acct->is_root();
    return $self->_mark_done( $entry );
}

sub update_entry {
    my( $self, $entry, $acct ) = @_;
    
    return $self->_update_entry( $entry );
} #update_entry

###################
# Private Methods #
###################

# cron entries will have the following fields :
#  * script - what to run
#  * repeats - a list of hashes with the following values : 
#       * repeat_infinite - true if this will always be repeated
#       * repeat_times - a number of times to repeat this; this decrements
#       * repeat_interval - how many seconds to repeat this
#  * scheduled_times - a list of epoc times this cron should be run
#  * next_time - epoc time this should be run next
#  * last_run - time this was last run

sub _init {
    my $self = shift;
    my $first_cron = new Yote::RootObj( {
	name   => 'recycler',
	enabled => 1,
	script => 'use Data::Dumper; my $recycled = Yote::ObjProvider::recycle_objects(); print STDERR Data::Dumper->Dump(["Recycled $recycled Objects"]);',
	repeats => [
	    new Yote::Obj( { repeat_interval => 2333, repeat_infinite => 1, repeat_times => 0 } ),
	    ],
	    
					} );
    $self->add_to_entries( $first_cron );
    $self->_update_entry( $first_cron );

} #_init

sub _mark_done {
    my( $self, $entry ) = @_;
    my $ran_at = _time();
    my $next_time;
    $entry->set_last_run( $ran_at );
    my $repeats = $entry->get_repeats();
    if( $repeats ) {
	my( @repeats ) = @$repeats;
	for( my $i=$#repeats; $i>=0; $i-- ) {
	    my $rep = $repeats[$i];
	    if( $rep->get_next_time() <= $ran_at ) {
		if( $rep->get_repeat_infinite() ) {
		    $rep->set_next_time( $rep->get_next_time() + $rep->get_repeat_interval() );
		    $rep->set_next_time( $ran_at + $rep->get_repeat_interval() ) if $rep->get_next_time() <= $ran_at;
		}
		elsif( $rep->get_next_time() <= $ran_at ) {
		    $rep->set_repeat_times( $rep->get_repeat_times() - 1 );
		    if( $rep->get_repeat_times() > 0 ) {
			$rep->set_next_time( $ran_at + $rep->get_repeat_interval() );
		    }
		    else {
			splice @$repeats, $i, 1;
			$rep->set_next_time( 0 );
		    }
		}
	    }
	    $next_time = $rep->get_next_time() && $next_time >= $rep->get_next_time() ? $next_time :  $rep->get_next_time();
	}
    } #if repeats
    my $times = $entry->get_scheduled_times();
    if( $times ) {
	my( @times ) = @$times;
 	for( my $i=$#times; $i>=0; $i-- ) {
	    my $sched = $times[$i];
	    if( $sched <= $ran_at ) {
		splice @$times, $i, 1;
	    }
	    elsif( $sched > $ran_at ) {
		$next_time = $sched < $next_time ? $sched : $next_time;
	    }
	}
    }
    $entry->set_next_time( $next_time );
    unless( $next_time ) {
	$entry->set_enabled( 0 );
    }
} #_mark_done

#
# Time is moved to its own sub in order to allow for modification for testing.
# Returns time in minutes
#
sub _time {
    return time/60;
} #_time

sub _update_entry {
    my( $self, $entry ) = @_;
    my $repeats = $entry->get_repeats();
    my $added_on = _time();
    my $next_time;
    if( $repeats ) {
	for my $rep (@$repeats) {
	    next unless $rep->get_repeat_infinite() || $rep->get_repeat_times();
	    $rep->set_next_time( $added_on + $rep->get_repeat_interval() );
	    $next_time ||= $rep->get_next_time();
	    $next_time = $rep->get_next_time() if $next_time > $rep->get_next_time();
	}
    } #if repeats
    my $times = $entry->get_scheduled_times();
    if( $times ) {
	for( my $i=$#$times; $i >= 0; $i-- ) {
	    splice( @$times, $i, 1 ) unless $times->[$i] > $added_on;
	}
	for my $sched ( @$times ) {
	    $next_time ||= ( $added_on + $sched );
	    $next_time = $sched if $sched < $next_time;
	}
    }
    $entry->set_next_time( $next_time );
    return $entry;
} #_update_entry


1;

__END__

=head1 NAME

Yote::Cron

=head1 SYNOPSIS

Yote::Cron is a subsystem in Yote that functions like a cron, allowing scripts to be run inside Yote. Rather than use
config files, this uses Yote objects to control the cron jobs. A cron editor is part of the Yote admin page.

=head1 DESCRIPTION

The Yote::Cron is set up on the yote system and runs every minute, checking if it should run 
any method that is attached to a yote object. It is a limited version of a cron system, as it
for now only registers methods with minutes and hours.

The Yote::Cron's public methods can only be called by an account with the __is_root flag set.

=head1 PUBLIC METHODS

=over 4

=item add_entry( $entry )

Ads an entry to this list. Takes a Yote::Obj that has the following data structure :

 * name - name of script to run
 * enabled - if true, this cron is active
 * script - what to run
 * repeats - a list of hashes with the following values : 
      * repeat_infinite - true if this will always be repeated
      * repeat_times - a number of times to repeat this; this decrements
      * repeat_interval - how many seconds to repeat this
 * scheduled times - a list of epoc times this cron should be run
 * next_time - epoc time this should be run next (volatile, should not be set by user)
 * last_run - time this was last run (volatile, should not be set by user)


=item entries()
 
Returns a list of the entries that should be run at the time this was called.

=item mark_done( $entry )

Marks this entry as done. This causes any repeat_times to decrement, and removes appropriate scheduled times.

=item update_entry( $entry )

This recalculates the next time this entry will be run.

=back

=head1 AUTHOR

Eric Wolf
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut


