package Yote::Cron;

use strict;

use DateTime;

use base 'Yote::Obj';

#
# The Cron object stores.
#

sub init {
    my $self = shift;
    $self->set__crond( {} );
} #init

sub add {
    my( $self, $data, $acct ) = @_;
    die "Incorrect permissions" unless $acct->__is_root();
    return $self->_add( $data );
}


sub _add {
    my( $self, $data ) = @_;

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
}

sub check {
    my( $self ) = @_;
    my $data = $self->get__crond();
    $self->{now} ||= DateTime->now();
    my( $min, $hr ) = ( $self->{now}->minute, $self->{now}->hour );
    print STDERR Data::Dumper->Dump([$data,$min,$hr,"CHK"]);
    $self->_activate( $data->{'*'}{'*'}  );
    $self->_activate( $data->{$min}{'*'} );
    $self->_activate( $data->{$min}{$hr} );
    $self->_activate( $data->{'*'}{$hr}  );
    return "";
} #check

sub _activate {
    my( $self, $items ) = @_;
    print STDERR Data::Dumper->Dump([$items,"ACTI"]);
    if( $items && @$items ) {
	for my $item (@$items) {
	    my( $obj_id, $method ) = @$item;
	    my $obj = Yote::ObjProvider::fetch( $obj_id );
	    eval {
		$obj->$method();
	    };
	}
    }
}


1;

__END__
