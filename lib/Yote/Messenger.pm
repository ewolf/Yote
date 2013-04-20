package Yote::Messenger;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';

use base 'Yote::Obj';

#
# Data is used for filtering messages
#    limit_start - for pagination
#    limit - max how many messages to return
#    sort - 'date', 'subject', 'name' default is date
#    sort_asc -  sort ascending flag
#    sort_desc - sort descending flag
#    filter - {  subject => 'text', from => messenger, older_than => time, newer_than => time, from_name => 'name' }
#
sub read_messages {
    my( $self, $data, $acct ) = @_;

    my $all_messages = $self->get__messages();
    
    if( $data->{filter} ) {
	if( $data->{filter}{newer_than} ) {
	    $all_messages = [ grep { $_->get_message()->get_sent() >= $data->{filter}{newer_than} } @$all_messages ];
	}
	if( $data->{filter}{older_than} ) {
	    $all_messages = [ grep { $_->get_message()->get_sent() <= $data->{filter}{older_than} } @$all_messages ];
	}
	if( $data->{filter}{from_name} ) {
	    $all_messages = [ grep {  $_->get_message()->get_from()->get_handle() =~ /$data->{filter}{from}/i  } @$all_messages ];
	}
	if( $data->{filter}{from} ) {
	    $all_messages = [ grep { $data->{filter}{from}->_is( $_->get_message()->get_from() )  } @$all_messages ];
	}
	if( $data->{filter}{subject} ) {
	    $all_messages = [ grep { $_->get_message()->get_subject() =~ /$data->{filter}{subject}/i } @$all_messages ];
	}
    } #filters
    
    if( $data->{sort} eq 'date' ) {
	if( $data->{sort_asc} ) {
	    $all_messages = [ sort { $a->get_sent() <=> $b->get_sent()  } @$all_messages ];
	} else {
	    $all_messages = [ sort { $b->get_sent() <=> $a->get_sent()  } @$all_messages ];
	}
    }
    elsif( $data->{sort} eq 'name' ) {
	if( $data->{sort_desc} ) {
	    $all_messages = [ sort { $b->get_from()->get_handle() cmp $a->get_from()->get_handle()  } @$all_messages ];
	} else {
	    $all_messages = [ sort { $a->get_from()->get_handle() cmp $b->get_from()->get_handle()  } @$all_messages ];
	}	
    }
    elsif( $data->{sort} eq 'subject' ) {
	if( $data->{sort_desc} ) {
	    $all_messages = [ sort { $b->get_subject() cmp $a->get_subject()  } @$all_messages ];
	} else {
	    $all_messages = [ sort { $a->get_subject() cmp $b->get_subject()  } @$all_messages ];
	}	
    }

    if( $data->{limit} ) {
	if( $data->{limit_start} ) {
	    $all_messages = [@$all_messages[$data->{limit_start}..$data->{limit}]];
	} 
	else {

	    $all_messages = [@$all_messages[0..$data->{limit}]];
	}
    }

    return $all_messages;

} #read_messages


#
# Data is :
#    recipients - list of receivers to send to
#    subject 
#    message
#
sub send_message {
    my( $self, $data, $acct ) = @_;
    
    my $recips = $data->{recipients};
    unless( $recips && @$recips ) {
	die "No Recipients given";
    }

    my $msg = new Yote::Obj();
    $msg->set_message( $data->{message} );
    $msg->set_subject( $data->{subject} );
    $msg->set_recipients( $recips );
    $msg->set_sent( time() );
    $msg->set_from( $self );

    for my $recip (@$recips) {
	my $envelope = {
	    message => $msg,
	    # read_time
	    # replied_time
	    # replies
	};

	# messages is private mostly because it can contain lots of data
	$recips->add_to__messages( $envelope );
    }

} #send_message

1;

__END__

=head1 NAME

Yote::Messenger

=head1 DESCRIPTION

A Yote::Messenger object is one that can send a message to an other object.

=head1 PUBLIC METHODS

=over 4

=item read_messages

Returns a list of messages. Takes a hash with the following fields

* filter - a hash with the following parameters

** subject

** from

** older_than

** newer_than

** from_name

* limit_start

* limit

* sort

* sort_asc

* sort_desc

* filter

=item send_message

Send a message to a number of recipients. Takes the following fields

* message

* recipients - list of recipient objects

* subject


=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut

