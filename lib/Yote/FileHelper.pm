package Yote::FileHelper;

use strict;

use base 'Yote::Obj';

use JSON;
use File::Temp qw/tempfile tempdir/;
use File::UStore;

sub _ingest {

    my $content_length = $ENV{CONTENT_LENGTH};
    my( $finding_headers, $finding_content, %content_data, %post_data, %file_helpers, $fn, $content_type );
    if( $ENV{HTTP_CONTENT_TYPE} =~ /boundary=(.*)/ ) {
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
    $post_data{d} = MIME::Base64::encode( to_json( _translate( from_json( MIME::Base64::decode($post_data{d}) ), \%file_helpers ) ), '' );

    return \%post_data;
} #_ingest

sub _translate {
    my( $structure, $file_helpers ) = @_;
    my $ref = ref( $structure );
    if( $ref eq 'HASH' ) {
	return { map { $_ => _translate( $structure->{$_}, $file_helpers ) } keys %$structure };
    } 
    elsif( $ref eq 'ARRAY' ) {
	return [ map { _translate( $_, $file_helpers ) } @$structure ];
    }
    else {
	return index( $structure, 'u' ) == 0 ? 'u' . to_json( $file_helpers->{ $structure } ) : $structure;
    }
} #_translate

sub _accept {
    my( $self, $filename ) = @_;

    my $store = File::UStore->new( path => $Yote::WebAppServer::UPLOAD_DIR, prefix => "yote_", depth => 5 );
    my $store_id = $store->add( $filename );
    $self->set_filename( $filename );
    $self->set_store_id( $store_id );

    unlink $filename;

} #_accept

sub Url {
    my $self = shift;
    my $store = File::UStore->new( path => $Yote::WebAppServer::UPLOAD_DIR, prefix => "yote_", depth => 5 );
    my $file_path = $store->getPath( $self->get_store_id() );
    return substr( $file_path, length( $Yote::WebAppServer::WEB_DIR ) )
    
}

1;
