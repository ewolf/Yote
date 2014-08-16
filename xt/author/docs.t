#!/usr/bin/perl

use strict;
use warnings;

use File::Spec::Functions qw( catdir updir );
use Test::More;
use Test::Pod;


use vars qw($VERSION);
$VERSION = '0.01';

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };


# -----------------------------------------------------
#               init
# -----------------------------------------------------

#
# Test documentation.
#
my( @poddirs ) = ( 'Yote/lib' );
all_pod_files_ok(
    all_pod_files( map { catdir updir, $_ } @poddirs )
    );

exit( 0 );

__END__
