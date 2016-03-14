package Samp::Acct;

use strict;
use warnings;
no warnings 'uninitialized';

use Yote::Server;

use base 'Yote::Server::ListContainer';

use Samp::Scenario;

sub _init {
    my $self = shift;
    $self->SUPER::_init();
    $self->add_entry( 'scenarios' );
}

sub _allowedUpdates {
    'current_scenario';
}

sub _lists {
    {
        scenarios => 'Samp::Scenario',
    };
}

sub _calculate {
    my( $self, $type, $listName, $scen, $idx ) = @_;
    if( $listName eq 'scenarios' ) {
        if( $type eq 'new_entry' ) {
            $self->set_current_scenario( $scen );
        } elsif( $type eq 'removed_entry' ) {
            my $sc = $self->get_scenarios;
            if( @$sc ) {
                $self->set_current_scenario( $idx > $#$sc ? $sc->[$#$sc] : $sc->[$idx] );
            } else {
                $self->set_current_product_line( undef );
            }
        }
    }
} #_calculate

1;

__END__
