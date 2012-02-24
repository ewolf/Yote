package Yote::Cache;

use strict;

sub new {
    my $pkg = shift;
    my $args = ref($_[0]) ? $_[0] : {@_};
    $args->{row_size} ||= 100000;
    my $class = ref( $pkg ) || $pkg;
    
    my $self = { 
        params => { row_size => $args->{row_size} },
        row_count => 0,
        hits => 0,
        misses => 0,
        STORE => {},
    };
    bless $self, $class;
    return $self;    
}

sub stow {
    my( $self, $id, $obj ) = @_;   
    $self->{STORE}{$id} = $obj;
}

sub fetch {
    my( $self, $id ) = @_;
    my $ret = $self->{STORE}{$id};
    defined($ret) ? ++$self->{hits} : ++$self->{missses};
    return $ret;
}


1;

__END__
