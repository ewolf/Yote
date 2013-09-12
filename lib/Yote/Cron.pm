package Yote::Cron;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.011';

use DateTime;

use base 'Yote::Obj';

# cron entries will have the following fields :
#  * script - what to run
#  * repeats - a list of hashes with the following values : 
#       * repeat_infinite - true if this will always be repeated
#       * repeat_times - a number of times to repeat this; this decrements
#       * repeat_interval - how many seconds to repeat this
#       * repeat_special - something like 'first tuesday of the month or something like that' ( can deal with this much later )
#  * scheduled_times - a list of epoc times this cron should be run
#  * run_next - epoc time this should be run next
#  * last_run - time this was last run

sub _init {
    my $self = shift;
    $self->set_entries( [] );
} #_init

sub mark_done {
    my( $self, $entry, $acct ) = @_;
    $self->_mark_done( $entry );
}

sub _mark_done {
    my( $self, $entry ) = @_;
    my $ran_at = time;
    my $next_time;
    $entry->set_last_run( $ran_at );
    my $repeats = $entry->get_repeats();
    if( $repeats ) {
	for my $rep (@$repeats) {
	    if( $rep->{ next_time } <= $ran_at ) {
		if( $rep->{ repeat_infinite } ) {
		    $rep->{ next_time } = $ran_at + $rep->{ repeat_interval };
		    $next_time ||= $rep->{ next_time };
		    $next_time = $rep->{ next_time } if $next_time > $rep->{ next_time };
		}
		else {
		    $rep->{ repeat_times }--;
		    if( $rep->{ repeat_times } ) {
			$rep->{ next_time } = $ran_at + $rep->{ repeat_interval };
			$next_time ||= $rep->{ next_time };
			$next_time = $rep->{ next_time } if $next_time > $rep->{ next_time };
		    }
		}
	    }
	    else {
		$next_time ||= $rep->{ next_time };
		$next_time = $rep->{ next_time } if $next_time > $rep->{ next_time };
	    }
	}
    } #if repeats
    if( $entry->{ scheduled_times } ) {
	$entry->{ scheduled_times } = [ grep { $_->{ next_time } <= $ran_at } @{ $entry->{ scheduled_times } } ];
	for my $entry ( @{ $entry->{ scheduled_times } } ) {
	    $next_time ||= ( $entry );
	    if( $next_time > $entry ) {
		$next_time = $entry;
	    }
	}
    }

    $entry->set_next_time( $next_time );

    unless( $next_time ) {
	$self->remove_from_entries( $entry );
	$self->add_to_completed_entries( $entry );
    }
} #_mark_done

sub add_entry {
    my( $self, $entry, $acct ) = @_;
    $self->add_to_entries( $entry );
    my $repeats = $entry->get_repeats();
    my $added_on = time;
    my $next_time;
    if( $repeats ) {
	for my $rep (@$repeats) {
	    $rep->{ next_time } = ( $added_on + $rep->{ repeat_interval } );
	    $next_time ||= $rep->{ next_time };
	    $next_time = $rep->{ next_time } if $next_time > $rep->{ next_time }
	}
    } #if repeats
    if( $entry->{ scheduled_times } ) {
	$entry->{ scheduled_times } = [ grep { $_ <= $added_on } @{ $entry->{ scheduled_times } } ];
	for my $sched ( @{ $entry->{ scheduled_times } } ) {
	    $sched->{ next_time } = ( $added_on + $sched );
	    $next_time ||= $sched;
	    $next_time = $sched if $sched < $next_time;
	}
    }
    $entry->set_next_time( $next_time );
    die "Entry  must contain a scheduled time or repeated time" unless $entry->get_next_time();
} #add_entry

sub entries {
    my $self = shift;
    my $now_running = time;
    return grep { $now_running >= $_->get_next_time() } @{ $self->get_entries() };
} #entries


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

=item mark_done

=item add_entry

Ads an entry to this list. Takes a Yote::Obj that has the following data structure :

 * script - what to run
 * repeats - a list of hashes with the following values : 
      * repeat_infinite - true if this will always be repeated
      * repeat_times - a number of times to repeat this; this decrements
      * repeat_interval - how many seconds to repeat this
      * repeat_special - something like 'first tuesday of the month or something like that' ( can deal with this much later )
 * scheduled times - a list of epoc times this cron should be run
 * next_time - epoc time this should be run next (volatile, should not be set by user)
 * last_run - time this was last run (volatile, should not be set by user)


=item entries
 
Returns a list of the entries that should be run now.

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut


