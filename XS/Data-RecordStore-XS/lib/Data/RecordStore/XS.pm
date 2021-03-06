package Data::RecordStore::XS;

use 5.022001;
use strict;
use warnings;

use Test::More;
use Data::Dumper;

require Exporter;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Data::RecordStore::XS ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';

require XSLoader;
XSLoader::load('Data::RecordStore::XS', $VERSION);

# Preloaded methods go here.
sub open_store {
    my $directory = pop @_;
    my $pkg = shift @_ || 'Data::RecordStore::XS';
    my $store = store_open( $directory );
    bless [ $store ], $pkg;
}

sub next_id {
    my $store = shift->[0];
    store_next_id( $store );
}


sub stow {
    my( $store, $data, $rid ) = @_;
    store_stow( $store->[0], $data, $rid || 0, 0 );
}

sub fetch {
    my( $store, $rid ) = @_;
    store_fetch( $store->[0], $rid );
}

sub has_id {
    my( $self, $rid ) = @_;
    store_has_id( $self->[0], $rid );
}

sub entry_count {
    entry_count_store( shift->[0] );
}

sub delete_record {
    my( $self, $rid ) = @_;
    store_delete( $self->[0], $rid );
}

sub recycle_id {
    my( $self, $rid ) = @_;
    store_recycle( $self->[0], $rid );
}

sub empty {
    store_empty( shift->[0] );
}

sub empty_recycler {
    store_empty_recycler( shift->[0] );
}

sub unlink_store {
    store_unlink( shift->[0] );
}

sub DESTROY {
    store_cleanup( shift->[0] );
}

sub _get_silo {
    my( $store, $sidx ) = @_;
    bless [ store_get_silo( $store->[0], $sidx ), "LIZ*" ], 'Data::RecordStore::Silo::XS';
}

#sub create_transaction {
    
#}

package Data::RecordStore::Silo::XS;

sub open_silo {
    my( $pkg, $template, $directory, $size ) = @_;
    my $template_size = $template =~ /\*/ ? 0 : do { use bytes; length( pack( $template ) ) };
    my $record_size = $size // $template_size;
    die "Data::RecordStore::Silo::XS->open_silo Cannot open a zero record sized fixed store" unless $record_size;
    my $silo = silo_open( $directory, $record_size );
    bless [ $silo, $template ], $pkg;
}

sub next_id {
    my $silo = shift->[0];
    next_id_silo( $silo );
}

sub put_record {
    my( $self, $id, $data ) = @_;
    die "Data::RecordStore::Silo::XS : index $id out of bounds." if $id < 1;
    my $to_write = pack ( $self->[1], ref $data ? @$data : $data );
    my $write_size = do { use bytes; length( $to_write ) };
    0 == put_record_silo( $self->[0], $id, $to_write, $write_size );
}

sub push {
    my( $self, $data ) = @_;
    my $id = $self->next_id;
    $self->put_record( $id, $data );
    return $id;
}

sub get_record {
    my( $self, $id ) = @_;
    [get_record_silo( $self->[0], $self->[1], length( $self->[1] ), $id )];
}

sub entry_count {
    entry_count_silo(shift->[0]);
}

sub empty {
    silo_empty( shift->[0] );
}

sub pop {
    my $self = shift;
    [pop_silo( $self->[0], $self->[1], length( $self->[1] ) )];
}

sub last_entry {
    my $self = shift;
    [last_entry_silo( $self->[0], $self->[1], length( $self->[1] ) ) ];
}

sub unlink_store {
    silo_unlink( shift->[0] );
}

# package Data::RecordStore::Transaction::XS;

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Data::RecordStore::XS - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Data::RecordStore::XS;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Data::RecordStore::XS, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

eric wolf, E<lt>wolf@E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2018 by eric wolf

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.22.1 or,
at your option, any later version of Perl 5 you may have available.


=cut
