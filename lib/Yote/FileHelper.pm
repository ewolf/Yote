package Yote::FileHelper;

##################################################################################
# This class serves as a wrapper so that files can be stored on the yote system. #
##################################################################################

use strict;
use warnings;

use vars qw($VERSION);
$VERSION = '0.012';

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
    my( $post_data, $file_helpers ) = @_;
    # go through the $post_data and translate any values into FileHelper object ids.
    $post_data->{d} = MIME::Base64::encode( to_json( __translate( from_json( MIME::Base64::decode($post_data->{d}) ), $file_helpers ) ), '' );

    return $post_data;
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
coyocanid@gmail.com
http://madyote.com

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut

