package Yote::WebAppServer;

use strict;
use warnings;
no warnings 'uninitialized';

use Data::Dumper;
use File::Slurp;
use File::stat;
use MIME::Base64;
use IO::Handle;
use JavaScript::Minifier;
use JSON;
use POSIX qw(strftime);

use vars qw($VERSION);

$VERSION = '0.24';


# ------------------------------------------------------------------------------------------
#      * INIT METHODS *
# ------------------------------------------------------------------------------------------

sub new {
    my( $pkg, $args ) = @_;
    my $class = ref( $pkg ) || $pkg;
    return bless { args => $args }, $class;
}

# ------------------------------------------------------------------------------------------
#      * PUBLIC METHODS *
# ------------------------------------------------------------------------------------------

# TODO : logging
sub accesslog {
    my( $msg ) = @_;
    my $t = strftime "%Y-%m-%d %H:%M:%S", gmtime;
    print $Yote::WebAppServer::ACCESS "$t : $msg\n";
}


sub errlog {
    my( $msg ) = @_;
    my $t = strftime "%Y-%m-%d %H:%M:%S", gmtime;
#    print $Yote::WebAppServer::ERR "$t : $msg\n";
}

sub iolog {
    my( $msg ) = @_;
    my $t = strftime "%Y-%m-%d %H:%M:%S", gmtime;
#    print $Yote::WebAppServer::IO "$t : $msg\n";
}

sub start {
    my $self = shift;

    # make sure the filehelper knows where the data directory is
    $self->{args}{webroot} = $self->{ args }{ yote_root } . '/html';
    $self->{args}{data_dir} = $self->{ args }{ yote_root } . '/data';
    $Yote::WebAppServer::LOG_DIR       = $self->{args}{yote_root} . '/log';
    $Yote::WebAppServer::FILE_DIR      = $self->{args}{data_dir} . '/holding';
    $Yote::WebAppServer::WEB_DIR       = $self->{args}{webroot};
    $Yote::WebAppServer::UPLOAD_DIR    = $self->{args}{webroot}. '/uploads';
    mkdir( $Yote::WebAppServer::FILE_DIR );
    mkdir( $Yote::WebAppServer::WEB_DIR );
    mkdir( $Yote::WebAppServer::UPLOAD_DIR );
    mkdir( $Yote::WebAppServer::LOG_DIR );

    open( $Yote::WebAppServer::IO,      '>>', "$Yote::WebAppServer::LOG_DIR/io.log" )
        && $Yote::WebAppServer::IO->autoflush;
    open( $Yote::WebAppServer::ACCESS,  '>>', "$Yote::WebAppServer::LOG_DIR/access.log" )
        && $Yote::WebAppServer::ACCESS->autoflush;
    open( $Yote::WebAppServer::ERR,     '>>', "$Yote::WebAppServer::LOG_DIR/error.log" )
        && $Yote::WebAppServer::ERR->autoflush;

    # open listener socket
    $self->{ web_socket } = $self->{ args }{ web_socket };

    # TODO : handle signals in the server itself, it will know how to handle wrap up
    $SIG{ TERM } = $SIG{ INT } = $SIG{ PIPE } = sub { 
        print STDERR "$0 $$ got signal. killing worker threads\n";   
        for my $cpid ( keys %{ $self->{ server_threads } } ) {
            kill 'SIGINT', $cpid;            
        }
        print STDERR "stopped all worker threads\n";   
        exit; 
    };
    $self->{ server_threads } = {};

    # launch server processes
    for( 1 .. $self->{args}{threads} ) {
        $self->_start_server_thread;
    } #creating threads

    # waitpid to keep correct number of processes
    while( (my $cpid = waitpid( -1, 0 )) > 0 ) {
        if( $cpid > 0 ) {
            $self->_start_server_thread;
        }
    }

} #start

sub _start_server_thread {
    my $self = shift;
    my $cpid = fork;

    if( $cpid ) { #parent
        $self->{ server_threads }{ $cpid } = 1;
    } 
    elsif( defined $cpid ) { #child
        $0 = 'yote appserver';

        $SIG{ TERM } = $SIG{ INT } = $SIG{ PIPE } = sub { 
            print STDERR "stopping worker thread $$\n";        
            exit; 
        };

        print STDERR "STARTING Server Thread $$";
        $self->serve;
        exit;
    }
    else {
        # TODO - report thread starting error
    }
} #_start_server_thread

#
# Accept and process incoming requests
#
sub serve {
    my $self = shift;
    while( my $fh = $self->{ web_socket }->accept ) {
        $ENV{ REMOTE_ADDR } = $fh->peerhost;
        $self->_process_http_request( $fh );
        $fh->close;
    } #process connection
} #serve

sub _process_http_request {
    my( $self, $socket ) = @_;
    my $req = <$socket>;

    delete $ENV{'HTTP_CONTENT-LENGTH'};
    while( my $hdr = <$socket> ) {
        $hdr =~ s/\s*$//s;
        last unless $hdr =~ /\S/;
        my( $key, $val ) = ( $hdr =~ /^([^:]+):(.*)/ );
        $ENV{ "HTTP_" . uc( $key ) } = $val;
    }
    my $content_length = $ENV{'HTTP_CONTENT-LENGTH'};
    if( $content_length > 5_000_000 ) { #TODO : make this into a configurable field
        $self->_do404( $socket );
        return;
    }

    # read certain length from socket ( as many bytes as content length
    my $data;
    if( $content_length && ! eof $socket) {
        my $read = read $socket, $data, $content_length;
    }

    #
    # There are two requests :
    #   * web page
    #   * command. starts with '_'. like _/{app id}/{obj id}/{command} or _/{command}
    #

    # Commands have the following structure :
    #   * a  - action
    #   * ai - app id to invoke command on
    #   * d  - data
    #   * e  - environment
    #   * gt - guest token
    #   * oi - object id to invoke command on
    #   * t  - login token for verification
    #   * gt - app (non-login) guest token for verification
    #

    my( $verb, $uri, $proto ) = split( /\s+/, $req );
    my $rest;
    ( $uri, $rest ) = ( $uri =~ /([^&?#]+)([&?#]?.*)/ );

    $uri ||= '/index.html';

    $ENV{PATH_INFO} = $uri;
    $ENV{REQUEST_METHOD} = $verb;

    ### ******* $uri **********

    my( @path ) = grep { $_ ne '' && $_ ne '..' } split( /\//, $uri );
    my( @return_headers );
    if( $path[0] eq '_' || $path[0] eq '_u' ) { # _ is normal yote io, _u is upload file
        iolog( "\n$uri" );
        errlog( $uri );
        my $path_start = shift @path;

        my( $guest_token, $token, $action, $obj_id, $app_id );

        push( @return_headers, "Content-Type: text/json; charset=utf-8");
        push( @return_headers, "Server: Yote" );
        if( $path_start eq '_' ) {
            ( $app_id, $obj_id, $action, $token, $guest_token ) = @path;
        }
        else { # an upload
            # TODO - verify this
            my $vars = Yote::FileHelper::__ingest( _parse_headers( $socket ) );
            $data        = $vars->{d};
            $token       = $vars->{t};
            $guest_token = $vars->{gt};
            $action      = pop( @path );
            $obj_id      = pop( @path );
            $app_id      = pop( @path );
        }

        # TODO : convert data to json and send that back and forth to the engine
        my $result = $self->_run_command( 
            {
                a  => $action,
                ai => $app_id,
                d  => MIME::Base64::decode( $data ),
                e  => {%ENV},
                oi => $obj_id,
                t  => $token,
                gt => $guest_token,
            } );
        print $socket "HTTP/1.0 200 OK\015\012";
        push( @return_headers, "Content-Type: text/json; charset=utf-8" );
        push( @return_headers,  "Access-Control-Allow-Origin: *" );
        push( @return_headers,  "Access-Control-Allow-Headers: accept, content-type, cookie, origin, connection, cache-control " );
        print $socket join( "\n", @return_headers )."\n\n";
        utf8::encode( $result );
        print $socket "$result";
        
    } #if a command on an object

    else {
        #
        # Serve up a web page. TODO : replace this with a library specialized in this.
        #

        my $root = $self->{args}{webroot};
        my $dest = '/' . join('/',@path);

        #
        # If the requested page matches a directory,
        # change the destination to index.html or, in the
        # case of a javascript directory, have it return
        # the _js/mini.js instead.
        #
        my $may_minify       = $dest =~ m~(.*)/js/?$~i;
        my $may_minify_debug = $dest =~ m~(.*)/JS/?$~;
        if( ( -d "$root/$dest" && ! -f "$root/$dest" ) || ( $may_minify_debug && ( -d $root . lc( "/$dest" ) && ! -f $root . lc( "/$dest" ) ) ) ) {
            #
            # Check for javascript directory to minify and
            # return a consolidated javascript file
            #                                                                                                                                   
                             
            if( $may_minify ) {
                $dest = _minify_dir( $root, lc($dest), $1, $may_minify_debug );
            }
            else {
                if( -e "$root/$dest/index.html" ) {
                    if( $dest eq '' || $dest eq '/' ) {
                        print $socket "HTTP/1.1 301 FOUND\015\012";
                        print $socket "Location: /index.html\n\n";
                        return;
                    }
                    print $socket "HTTP/1.1 301 FOUND\015\012";
                    print $socket "Location: $dest/index.html\n\n";
                    return;
                }
            }
        } 

        #
        # Read in the headers
        #
        if( open( my $IN, '<', "$root/$dest" ) ) {
            accesslog( "$uri from [ $ENV{ REMOTE_ADDR } ][ $ENV{ HTTP_REFERER } ]" );

            print $socket "HTTP/1.0 200 OK\015\012";
            my $is_html = 0;
            if( $dest =~ /\.js$/i ) {
                push( @return_headers, "Content-Type: text/javascript" );
            }
            elsif( $dest =~ /\.css$/i ) {
                push( @return_headers, "Content-Type: text/css" );
            }
            elsif( $dest =~ /\.(jpg|gif|png|jpeg)$/i ) {
                push( @return_headers, "Content-Type: image/$1" );
            }
            elsif( $dest =~ /\.(tar|gz|zip|bz2)$/i ) {
                push( @return_headers, "Content-Type: image/$1" );
            }
            else {
                push( @return_headers, "Content-Type: text/html" );
                $is_html = 1;
            }
            push( @return_headers, "Server: Yote" );
            print $socket join( "\n", @return_headers )."\n\n";

            my $size = -s "<$root/$dest";
            push( @return_headers, "Content-length: $size" );
            push( @return_headers,  "Access-Control-Allow-Origin: *" );
            push( @return_headers,  "Access-Control-Allow-Headers: accept, content-type, cookie, origin, connection, cache-control " );

            my $buf;
            while( read( $IN,$buf, 8 * 2**10 ) ) {		
                print $socket $buf;
            }
            close( $IN );
        } else {
            accesslog( "404 not found : $uri from [ $ENV{ REMOTE_ADDR } ][ $ENV{ HTTP_REFERER } ]" );
            errlog( "404 NOT FOUND ($$) : $@,$! [$root/$dest]");
            $self->_do404( $socket );
        }
    } #serve html

    return;
} #_process_http_request

sub _run_command {
    my( $self, $cmd ) = @_;

    #open socket to engine and communicate with it
    my $sock = new IO::Socket::INET( "127.0.0.1:$self->{args}{internal_port}" );

    my $json_cmd = to_json( $cmd );
    print $sock "$json_cmd\n\n";

    my $res = <$sock>;

    $sock->close;

    return $res;

} #_run_command

# ------------------------------------------------------------------------------------------
#      * PRIVATE METHODS *
# ------------------------------------------------------------------------------------------


sub _do404 {
    my( $self, $socket ) = @_;
    print $socket "HTTP/1.0 404 NOT FOUND\015\012Content-Type: text/html\n\nERROR : 404\n";
}



#
# 
#
sub _parse_headers {
    my $socket = shift;
    my $content_length = $ENV{CONTENT_LENGTH} || $ENV{'HTTP_CONTENT-LENGTH'} || $ENV{HTTP_CONTENT_LENGTH};
    my( $finding_headers, $finding_content, %content_data, %post_data, %file_helpers, $fn, $content_type );
    my $boundary_header = $ENV{HTTP_CONTENT_TYPE} || $ENV{'HTTP_CONTENT-TYPE'} || $ENV{CONTENT_TYPE};
    if( $boundary_header =~ /boundary=(.*)/ ) {
        my $boundary = $1;
        my $counter = 0;
        # find boundary parts
        while($counter < $content_length) {
            $_ = <$socket>;
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
                if( /^\s*$/s ) {  # got a blank line, so end of headers
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
    return ( \%post_data, \%file_helpers );
} #_parse_headers

sub _minify_dir {
    my( $root, $source_dir, $source_root, $is_debug ) = @_;
    #
    # Check if there are files in the directory that are newer than the minified file
    # of if the minified file does not exist
    #
    my $minidir = "$source_root/_js";
    my $minifile = "$root/$minidir/mini.js";
    my $debugfile = "$root/$minidir/maxi.js";
    
    if( ! -d "$root/$minidir" ) {
        mkdir( "$root/$minidir" ); 
    }

    opendir( my $SOURCEDIR, $root . lc( "/$source_dir" ) );
    my( @js_files, $latest_time );
    while( my $fn = readdir $SOURCEDIR ) {
        if( $fn =~ /\.js$/ ) {
            my $file = "$root/$source_dir/$fn";
            push @js_files, $file;
            my $lastmod = stat($file)->mtime;

            $latest_time ||= $lastmod;
            $latest_time = $latest_time < $lastmod ? $lastmod : $latest_time;
        }
    }
    my $minitime = -e $minifile ? stat($minifile)->mtime : 0;

    if( ! -f $minifile || $minitime < $latest_time ) {
        my $mini_buf = '';
        my $debug_buf = '';
        # make sure base jquery comes first, followed by other jquery
        # make sure that yote comes before yote.util
        for my $f (sort { ( $a =~ /jquery(-[0-9.]*)?(\.min)?\.js$/ || ($a =~ /jquery/ && $b !~ /jquery/ ) || $b =~ /yote.template/ ) ? -1 : 1
                   } @js_files) {
            my $js = read_file( $f );
            $mini_buf .= $f =~ /\.min\.js$/ ? $js : JavaScript::Minifier::minify(input => $js);
            $debug_buf .= "$js\n";
        }
        write_file( $minifile, $mini_buf );
        write_file( $debugfile, $debug_buf );
    }
    return $is_debug ? "$minidir/maxi.js" : "$minidir/mini.js";
} #_minify_dir

1;

__END__

=head1 NAME

Yote::WebAppServer - This is the app server engine that provides server threads and all javascript perl IO.

=head1 DESCRIPTION

This starts an appslication server running on a specified port and hooked up to a specified datastore.
Additional parameters are passed to the datastore.

=head1 PUBLIC METHODS

=over 4

=item accesslog( msg )

Write the message to the access log

=item errlog( msg )

Write the message to the error log

=item iolog( msg )

Writes to an IO log for client server communications

=item lock_object( obj_id )

Locks the given object id for use by this process only until it is unlocked.

=item new

Returns a new WebAppServer.

=item serve

=item start

=item unlock_objects( @list_of_obj_ids )

Unlocks the objects referenced by the ids passed in. 

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
