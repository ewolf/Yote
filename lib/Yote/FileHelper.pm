package Yote::FileHelper;

use strict;
use warnings;

use base 'Yote::Obj';

use JSON;
use File::Temp qw/tempfile tempdir/;
use File::UStore;


# ------------------------------------------------------------------------------------------
#      * PUBLIC API Methods *
# ------------------------------------------------------------------------------------------

sub Url {
    my $self = shift;
    my $store = File::UStore->new( path => $Yote::WebAppServer::UPLOAD_DIR, prefix => "yote_", depth => 5 );
    my $file_path = $store->getPath( $self->get_store_id() );
    return substr( $file_path, length( $Yote::WebAppServer::WEB_DIR ) )
} #Url


# ------------------------------------------------------------------------------------------
#      * Private Methods *
# ------------------------------------------------------------------------------------------


sub __ingest {

    my $content_length = $ENV{CONTENT_LENGTH};
    my( $finding_headers, $finding_content, %content_data, %post_data, %file_helpers, $fn, $content_type );
    my $boundary_header = $ENV{HTTP_CONTENT_TYPE} || $ENV{CONTENT_TYPE};
    if( $boundary_header =~ /boundary=(.*)/ ) {
	my $boundary = $1;
	my $counter = 0;
	# find boundary parts
	while($counter < $content_length) {
	    $_ = <STDIN>;
	    if( /$boundary/s ) {
		last if $1;
		$finding_headers = 1;
		$finding_content = 0;
		if( $content_data{ name } && !$content_data{ filename } ) {
		    $post_data{ $content_data{ name } } =~ s/[\n\r]*$//;
		}
		%content_data = ();
		undef $fn;
	    }
	    elsif( $finding_headers ) {
		if( /^\s*$/s ) {
		    $finding_headers = 0;
		    $finding_content = 1;
		    if( $content_data{ name } && $content_data{ filename } ) {
			my $name = $content_data{ name };
			
			$fn = File::Temp->new( UNLINK => 0, DIR => $Yote::WebAppServer::FILE_DIR );
			$file_helpers{ $name } = {
			    filename     => $fn->filename,
			    content_type => $content_type,
			}
		    }
		} else {
		    my( $hdr, $val ) = split( /:/, $_ );
		    if( lc($hdr) eq 'content-disposition' ) {
			my( $hdr_type, @parts ) = split( /\s*;\s*/, $val );
			$content_data{ $hdr } = $hdr_type;
			for my $part (@parts) {
			    my( $k, $d, $v ) = ( $part =~ /([^=]*)=(['"])?(.*)\2\s*$/s );
			    $content_data{ $k } = $v;
			}
		    } elsif( lc( $hdr ) eq 'content-type' && $val =~ /^([^;]*)/ ) {
			$content_type = $1;
		    }
		}
	    }
	    elsif( $finding_content ) {
		if( $fn ) {
		    print $fn $_;
		} else {
		    $post_data{ $content_data{ name } } .= $_;
		}
	    } else {

	    }
	    $counter += length( $_ );

	} #while
    } #if has a boundary content type
    # go through the $post_data and translate any values into FileHelper object ids.
    $post_data{d} = MIME::Base64::encode( to_json( __translate( from_json( MIME::Base64::decode($post_data{d}) ), \%file_helpers ) ), '' );

    return \%post_data;
} #__ingest

sub __translate {
    my( $structure, $file_helpers ) = @_;
    my $ref = ref( $structure );
    if( $ref eq 'HASH' ) {
	return { map { $_ => __translate( $structure->{$_}, $file_helpers ) } keys %$structure };
    } 
    elsif( $ref eq 'ARRAY' ) {
	return [ map { __translate( $_, $file_helpers ) } @$structure ];
    }
    else {
	return index( $structure, 'u' ) == 0 ? 'u' . to_json( $file_helpers->{ $structure } ) : $structure;
    }
} #__translate

sub __accept {
    my( $self, $filename ) = @_;

    my $store = File::UStore->new( path => $Yote::WebAppServer::UPLOAD_DIR, prefix => "yote_", depth => 5 );
    my $store_id = $store->add( $filename );
    $self->set_filename( $filename );
    $self->set_store_id( $store_id );

    unlink $filename;

} #__accept

1;

__END__

=head1 NAME

Yote::FileHelper

=head1 DESCRIPTION

This module is essentially a private module and its methods will not be called directly by programs.
The Yote::FileHelper is automatically invoked by Yote::WebAppServer to injest uploaded files into the yote system.
The Yote::FileHelper then is used as a yote object that exposes the url where the file exists.

=head1 PUBLIC METHODS

=over 4

=item Url

Returns a url on the yote system where the file can be accessed.

=back

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut

