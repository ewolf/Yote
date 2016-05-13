package Yote::Server::Obj;

use strict;
use warnings;
no warnings 'uninitialized';
    
use base 'Yote::Obj';

sub _log {
    Yote::Server::_log(shift);
}

$Yote::Server::Obj::PKG2METHS = {};
sub __discover_methods {
    my $pkg = shift;
    my $meths = $Yote::Server::Obj::PKG2METHS->{$pkg};
    if( $meths ) {
        return $meths;
    }

    no strict 'refs';
    my @m = grep { $_ !~ /::/ } keys %{"${pkg}\::"};
    if( $pkg eq 'Yote::Server::Obj' ) { #the base, presumably
        return [ grep { $_ !~ /^(_|[gs]et_|(can|[sg]et|VERSION|AUTOLOAD|DESTROY|CARP_TRACE|BEGIN|import|isa|PKG2METHS|ISA)$)/ } @m ];
    }

    my %hasm = map { $_ => 1 } @m;
    for my $class ( @{"${pkg}\::ISA" } ) {
        next if $class eq 'Yote::Server::Obj' || $class eq 'Yote::Obj';
        my $pm = __discover_methods( $class );
        push @m, @$pm;
    }
    
    my $base_meths = __discover_methods( 'Yote::Server::Obj' );
    my( %base ) = map { $_ => 1 } 'AUTOLOAD', @$base_meths;
    $meths = [ grep { $_ !~ /^(_|[gs]et_|(can|[sg]et|VERSION|AUTOLOAD|DESTROY|BEGIN|import|isa|PKG2METHS|ISA)$)/ && ! $base{$_} } @m ];
    $Yote::Server::Obj::PKG2METHS->{$pkg} = $meths;
    
    $meths;
} #__discover_methods

# when sending objects across, the format is like
# id : { data : { }, methods : [] }
# the methods exclude all the methods of Yote::Obj
sub _callable_methods {
    my $self = shift;
    my $pkg = ref( $self );
    __discover_methods( $pkg );
} # _callable_methods

sub get {
    my( $self, $fld, $default ) = @_;
    if( index( $fld, '_' ) == 0 ) {
        die "Cannot get private field $fld";
    }
    $self->_get( $fld, $default );
} #get


sub _get {
    my( $self, $fld, $default ) = @_;
    if( ! defined( $self->{DATA}{$fld} ) && defined($default) ) {
        if( ref( $default ) ) {
            $self->{STORE}->_dirty( $default, $self->{STORE}->_get_id( $default ) );
        }
        $self->{STORE}->_dirty( $self, $self->{ID} );
        $self->{DATA}{$fld} = $self->{STORE}->_xform_in( $default );
    }
    $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
} #_get


sub set {
    my( $self, $fld, $val ) = @_;
    if( index( $fld, '_' ) == 0 ) {
        die "Cannot set private field";
    }
    my $inval = $self->{STORE}->_xform_in( $val );
    $self->{STORE}->_dirty( $self, $self->{ID} ) if $self->{DATA}{$fld} ne $inval;
    $self->{DATA}{$fld} = $inval;
    
    $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
} #set

1;
