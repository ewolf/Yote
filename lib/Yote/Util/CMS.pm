package Yote::Util::CMS;

use strict;

use base 'Yote::Obj';

use Time::Piece;

sub fetch_specific_content_node {
    my( $self, $data, $acct ) = @_;

    my $path   = $data->{path};
    my $starts = $data->{starts};
    my $lang   = $data->{lang};
    my $region = $data->{region};

    # CHECK PATH
    if( $path ) {
	my $working_node = $self->get__path_nodes( {} )->{ $path };
	return undef unless $working_node;
	return $working_node->fetch_specific_content_node( { starts => $starts,
							     lang   => $lang,
							     region => $region,
							   } );
    }
    
    # CHECK DATE
    if( $starts ) {
	my( $date_node ) = sort { $a->get_start_time() gt $b->get_start_time() } grep { $_->get_start_time() le $starts } @{ $self->get__date_nodes( {} ) };
	return undef unless $date_node;
	return $date_node->fetch_specific_content_node( { lang   => $lang,
							  region => $region, } );
    }

    # CHECK LANG
    if( $lang ) {
	my( $lang_node ) = $self->get__lang_nodes( {} )->{ $lang };
	return undef unless $lang_node;
	return $lang_node->fetch_specific_content_node( { region => $region, } );
    }

    # CHECK REGION
    if( $region ) {
	my( $region_node ) = $self->get__region_nodes( {} )->{ $region };
	return undef unless $region_node;
	return $region_node;
    }
    
    return $self;
    
} #fetch_specific_content_node

sub fetch_content_node {
    my( $self, $data, $acct ) = @_;

    # returns the content node specified by the data and returns it. 
    my $working_node = $self->get__path_nodes( {} )->{ $data->{path} } || $self;
    
    # check if there is anything date specific
    my $now = $data->{starts} || localtime->strftime("%Y-%m-%d:%H:%M");
    my( $date_node ) = sort { $a->get_start_time() gt $b->get_start_time() } 
                       grep { $_->get_start_time() le $now && ( ( ! $_->get_end_time() ) || $_->get_end_time() gt $now ) } @{$working_node->get__date_nodes( [] )};
    if( $date_node ) {
	my $res = $date_node->fetch_content_node( $data, $acct );
	return $res if $res;
    }

    # check if there is anything language specific
    my( $lang_node ) = $working_node->get__lang_nodes( {} )->{ $data->{lang} };
    if( $lang_node ) {
	my $res = $lang_node->fetch_content_node( $data, $acct );
	return $res if $res;
    }

    # check if there is anything region specific
    my( $region_node ) = $working_node->get__region_nodes( {} )->{ $data->{region} };
    if( $region_node ) {
	my $res = $region_node->fetch_content_node( $data, $acct );
	return $res if $res;
    }
    return $self;

} #fetch_content_node

sub attach_content {
    # specifically for textual content
    my( $self, $data, $acct ) = @_;

    my $path    = $data->{path};
    my $starts  = $data->{starts};
    my $ends    = $data->{ends};
    my $lang    = $data->{lang};
    my $region  = $data->{region};
    my $content = $data->{content};
    my $mime_type = $data->{mime_type};

    if( $path ) {
	my $path_node = $self->get__path_nodes( {} )->{ $path };
	unless( $path_node ) {
	    $path_node = new Yote::Util::CMS();
	    $self->get__path_nodes()->{ $path } = $path_node;
	}
	return $path_node->attach_content( { starts => $starts,
					     ends   => $ends,
					     lang   => $lang,
					     region => $region,
					     content => $content,
					     mime_type => $mime_type,
					   } );
    } # has path

    # put these in in order of importance
    if( $starts ) {
	my $date_nodes = $self->get__date_nodes( {} );
	my( $date_node ) = grep { $_->get_start_time() eq $starts } @$date_nodes;
	unless( $date_node ) {
	    $date_node = new Yote::Util::CMS();
	    $date_node->set_start_time( $starts );
	    $date_node->set_end_time( $ends ) if $ends;
	    unshift @$date_nodes, $date_node;
	}
	return $date_node->attach_content( { lang    => $lang,
					     region  => $region,
					     content => $content,
					     mime_type => $mime_type,
					   } );
    } #has starts

    if( $lang ) {
	my $lang_node = $self->get__lang_nodes( {} )->{ $lang };
	unless( $lang_node ) {
	    $lang_node = new Yote::Util::CMS();
	    $self->get__lang_nodes()->{ $lang } = $lang_node;
	}
	return $lang_node->attach_content( { region => $region, 
					     content => $content,
					     mime_type => $mime_type, } );
    }
    
    if( $region ) {
	my $region_node = $self->get__region_nodes( { } )->{ $region };
	unless( $region_node ) {
	    $region_node = new Yote::Util::CMS();
	    $self->get__region_nodes()->{ $region } = $region_node;
	}
	return $region_node->attach_content( { content => $content,
					       mime_type => $mime_type, } );
    }

    $self->set_mime_type( $mime_type );
    if( ref( $content ) ) {
	$self->set_content( $content->Url() );
    } else {
	$self->set_content( $content );
    }
    return $self;
} #attach_content

1;

__END__


The CMS has a number of resources specified by string.
A String can look up a CMS node.

The node may have subnodes which are accessed by rules, such as language and a date to start showing.

Incoming data may be :
  * language
  * region

There is a master node with the following set up

Node
   - content node [ with content type ( can be html, string, image or other media ), etc ]
   - start time (optional only if not in a sub date node) in the format YYYY-MM-DD:H-M
   - end time (optional)
   - _path_nodes { hash of strings to subnodes } 
   - _dates [ list of date/subnode pairs ]
   - _languages { hash of langauge to subnodes }
   - _regions { hash of region to subnodes }

The rule are checked starting with the main CMS node like so :

Input data : { node     : 'some_node',
               language : 'english',
               region   : 'north america',
              }
The master node looks up some_node to get a working node.
  If it cannot find it, it uses itself as the working node.
  If it finds it, it uses what it finds as the working node.

The working node now checks for the presense of date subnodes.
If it finds one, it looks through these ( they are sorted in descending date order )
to find the most recent date that the current date is after its start
If it finds none, it stays on this node, otherwise it sets the current working node to the node specified by that date

 language to see if it has any language specific versions of itself

Uploading something to the CMS is as follows :

data 
{
  content    - some content object
  path       - an identifying string
  languages  - [ list of languages allowed for this update. None to include all ]
  start      - datetime string this should start on. if this is present. in the format YYYY-MM-DD:H-M
  end        - datetime string this should end on. if this is present
  region     - [ list of regions this should be good for ]
}
 
Given that upload, the CMS finds a place for it.


=head1 NAME

Yote::Util::CMS - a simple CMS

=head2 DESCRIPTION

This is a simple CMS with regionalization and scheduling.
