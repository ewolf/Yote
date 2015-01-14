package Yote::IO::FixedStore;

use strict;

use Fcntl qw( SEEK_SET LOCK_EX LOCK_UN );
use File::Touch;
use Data::Dumper;

sub new {
    my( $pkg, $template, $filename, $size ) = @_;
    my $class = ref( $pkg ) || $pkg;
    my $FH;
    touch $filename;
    open $FH, "+<$filename" or die "$@ $!";
    return bless { TMPL => $template, 
                   SIZE => $size || do { use bytes; length( pack( $template ) ) },
                   FILENAME => $filename,
                   FILEHANDLE => $FH,
    }, $class;
} #new

sub size {
    return shift->{SIZE};
}

#
# Add a record to the end of this store. Returns the new id.
#
sub push {
    my( $self, $data ) = @_;

    my $fh = $self->{FILEHANDLE};
    flock $fh, LOCK_EX;

    my $next_id = 1 + $self->entries;
    $self->put_record( $next_id, $data );
    
    flock $fh, LOCK_UN;

    return $next_id;
} #push

#
# Remove the last record and return it.
#
sub pop {
    my( $self ) = @_;

    my $fh = $self->{FILEHANDLE};
    flock $fh, LOCK_EX;

    my $entries = $self->entries;
    my $ret = $self->get_record( $entries );

    truncate $self->{FILEHANDLE}, $entries * $self->{SIZE};
    
    flock $fh, LOCK_UN;

    return $ret;
    
} #pop

#
# The first record has id 1, not 0
#
sub put_record {
    my( $self, $idx, $data ) = @_;
    my $fh = $self->{FILEHANDLE};
    sysseek $fh, $self->{SIZE} * ($idx-1), SEEK_SET;
    my $to_write = pack ( $self->{TMPL}, ref $data ? @$data : $data );
    my $to_write_length = do { use bytes; length( $to_write ); };
    if( $to_write_length < $self->{SIZE} ) {
        my $del = $self->{SIZE} - $to_write_length;
        $to_write .= "\0" x $del;
        my $to_write_length = do { use bytes; length( $to_write ); };
        die "$to_write_length vs $self->{SIZE}" unless $to_write_length == $self->{SIZE};
    }
    syswrite $fh, $to_write;
} #put_record

sub get_record {
    my( $self, $idx ) = @_;
    my $fh = $self->{FILEHANDLE};
    sysseek $fh, $self->{SIZE} * ($idx-1), SEEK_SET;
    sysread $fh, my $data, $self->{SIZE};
    return [unpack( $self->{TMPL}, $data )];
} #get_record

sub entries {
    # return how many entries this index has
    my $self = shift;
    my $filesize = -s $self->{FILENAME};
    print STDERR Data::Dumper->Dump([$filesize,$self->{SIZE},"EN"]);
    return int( $filesize / $self->{SIZE} );
}

sub next_id {
    my( $self, $idx ) = @_;

    my $fh = $self->{FILEHANDLE};
    flock $fh, LOCK_EX;

    my $next_id = 1 + $self->entries;
    $self->put_record( $next_id, [] );

    flock $fh, LOCK_UN;
    print STDERR Data::Dumper->Dump(["RETURN", $next_id]);
    return $next_id;
} #next_id

1;

__END__
