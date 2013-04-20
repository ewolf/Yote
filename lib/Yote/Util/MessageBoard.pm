package Yote::Util::MessageBoard;

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.01';

use base 'Yote::Obj';

#
# Data is :
#    subject
#    message
#    from
#
sub post {
    my( $self, $data, $acct ) = @_;

    my $msg = new Yote::Obj();
    $msg->set_message( $data->{message} );
    $msg->set_subject( $data->{subject} );
    $msg->set_sent( time() );
    if( $data->{from} && $acct->_is( $data->{from}->get_account() ) ) {
	$msg->set_from( $data->{from} );
    } 
    else {
	$msg->set_from( $acct );
    }

    $self->add_to__messages( $msg );

} #post


#
# Data is used for filtering messages
#    limit_start - for pagination
#    limit - max how many messages to return
#    sort - 'date', 'subject', 'name' default is date
#    sort_asc -  sort ascending flag
#    sort_desc - sort descending flag
#    filter - {  subject => 'text', from => messenger, older_than => time, newer_than => time, from_name => 'name' }
#
sub read {
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

} #read

1;

__END__
