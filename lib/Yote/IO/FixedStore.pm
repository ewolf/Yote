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

sub filehandle {
    my $self = shift;
    close $self->{FILEHANDLE};
    open $self->{FILEHANDLE}, "+<$self->{FILENAME}";
    return $self->{FILEHANDLE};
}


sub unlink {
    # TODO : more checks
    my $self = shift;
    close $self->filehandle;
    unlink $self->{FILENAME};
}

sub size {
    return shift->{SIZE};
}

#
# Add a record to the end of this store. Returns the new id.
#
sub push {
    my( $self, $data ) = @_;

    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;

    my $next_id = 1 + $self->entries;
    $self->put_record( $next_id, $data );
    
#    flock $fh, LOCK_UN;

    return $next_id;
} #push

#
# Remove the last record and return it.
#
sub pop {
    my( $self ) = @_;

#    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;

    my $entries = $self->entries;
    return undef unless $entries;
    my $ret = $self->get_record( $entries );
    truncate $self->filehandle, ($entries-1) * $self->{SIZE};
    
#    flock $fh, LOCK_UN;

    return $ret;
    
} #pop

#
# The first record has id 1, not 0
#
sub put_record {
    my( $self, $idx, $data ) = @_;
    my $fh = $self->filehandle;
    sysseek $fh, $self->{SIZE} * ($idx-1), SEEK_SET or die "Could not seek : $@ $!";
    my $to_write = pack ( $self->{TMPL}, ref $data ? @$data : $data );

    my $to_write_length = do { use bytes; length( $to_write ); };
    if( $to_write_length < $self->{SIZE} ) {
        my $del = $self->{SIZE} - $to_write_length;
        $to_write .= "\0" x $del;
        my $to_write_length = do { use bytes; length( $to_write ); };
        die "$to_write_length vs $self->{SIZE}" unless $to_write_length == $self->{SIZE};
    }
    my $swv = syswrite $fh, $to_write;
    defined( $swv ) or die "Could not write : $@ $!";
    return 1;
} #put_record

sub get_record {
    my( $self, $idx ) = @_;
    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;
    sysseek $fh, $self->{SIZE} * ($idx-1), SEEK_SET or die "Could not seek ($self->{SIZE} * ($idx-1)) : $@ $!";
    my $srv = sysread $fh, my $data, $self->{SIZE};
    defined( $srv ) or die "Could not read : $@ $!";
#    flock $fh, LOCK_UN;
    return [unpack( $self->{TMPL}, $data )];
} #get_record

sub entries {
    # return how many entries this index has
    my $self = shift;
    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;
    my $filesize = -s $self->{FILENAME};
#    flock $fh, LOCK_UN;
    return int( $filesize / $self->{SIZE} );
}

#
# Empties out this file. Eeek
#
sub empty {
    my $self = shift;
    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;
    truncate $self->{FILENAME}, 0;
#    flock $fh, LOCK_UN;
    return undef;
} #empty

#
# Makes sure there at least this many entries.
#
sub ensure_entry_count {
    my( $self, $count ) = @_;
    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;

    my $entries = $self->entries;
    if( $count > $entries ) {
        for( (1+$entries)..$count ) {
            $self->put_record( $_, [] );            
        }
    } 

#    flock $fh, LOCK_UN;
} #ensure_entry_count

sub next_id {
    my( $self ) = @_;

    my $fh = $self->filehandle;
#    flock $fh, LOCK_EX;
    my $next_id = 1 + $self->entries;
    print STDERR Data::Dumper->Dump(["CREATING $next_id"]) if $self->{TMPL} eq 'LII';
    $self->put_record( $next_id, [] );
#    flock $fh, LOCK_UN;
    return $next_id;
} #next_id

1;

__END__
