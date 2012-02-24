package Yote::Test::DummyCache;

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

sub stow {}
sub fetch {}


1;

__END__
