package GServ::ObjProvider;

use strict;

use feature ':5.10';

use GServ::Array;
use GServ::Hash;
use GServ::Obj;
use GServ::ObjIO;

use Data::Dumper;

use Exporter;
use base 'Exporter';

our @EXPORT_OK = qw(fetch stow a_child_of_b);

$GServ::ObjProvider::DIRTY = {};

# --------------------  
#   PACKAGE METHODS
# -------------------- 

sub fetch_root {
    my $root = fetch( 1 );

    unless( $root ) {
        $root = new GServ::Obj;
        stow( $root );
    }

    return $root;
} #fetch_root;

sub xpath {
    my $path = shift;
    return xform_out( GServ::ObjIO::xpath( $path ) );
}

sub xpath_count {
    my $path = shift;
    return GServ::ObjIO::xpath_count( $path );
}

sub fetch {
    my( $id ) = @_;

    # 
    # Return the object if we have a reference to its dirty state.
    #
    my $dirty = $GServ::ObjProvider::DIRTY->{$id};
    return $dirty if $dirty;

    my $obj_arry = GServ::ObjIO::fetch( $id );
    if( $obj_arry ) {
        my( $id, $class, $data ) = @$obj_arry;
        given( $class ) {
            when('ARRAY') {
                my( @arry );
                tie @arry, 'GServ::Array', $id, map { xform_out($_) } @$data;
                return \@arry;
            }
            when('HASH') {
                my( %hash );
                tie %hash, 'GServ::Hash', __ID__ => $id, map { $_ => xform_out($data->{$_}) } keys %$data;
                return \%hash;
            }
            default {
                eval("use $class");
                my $obj = $class->new;
                $obj->{DATA} = $data;
                $obj->{ID} = $id;
                return $obj;
            }
        }
    }
    return undef;
} #fetch

sub get_id {
    my $ref = shift;
    my $class = ref( $ref );
    given( $class ) {
        when('GServ::Array') {
            return $ref->[0];
        }
        when('ARRAY') {
            my $tied = tied @$ref;
            if( $tied ) {
                return $tied->[0] || GServ::ObjIO::get_id( "ARRAY" );
            }
            my( @data ) = @$ref;
            my $id = GServ::ObjIO::get_id( $class );
            tie @$ref, 'GServ::Array', $id;
            push( @$ref, @data );
            dirty( $ref, $id );
            return $id;
        }
        when('GServ::Hash') {
            return $ref->{__ID__};
        }
        when('HASH') {
            my $tied = tied %$ref;
            if( $tied ) {
                return $tied->{__ID__} || GServ::ObjIO::get_id( "HASH" );
            } 
            my $id = GServ::ObjIO::get_id( $class );
            my( %vals ) = %$ref;
            tie %$ref, 'GServ::Hash', __ID__ => $id;
            for my $key (keys %vals) {
                $ref->{$key} = $vals{$key};
            }
            dirty( $ref, $id );
            return $id;
        }
        default {
            $ref->{ID} ||= GServ::ObjIO::get_id( $class );
            return $ref->{ID};
        }
    }
} #get_id

sub a_child_of_b {
    my( $a, $b, $seen ) = @_;
    my $bref = ref( $b );
    return 0 unless $bref && ref($a);
    $seen ||= {};
    my $bid = get_id( $b );
    return 0 if $seen->{$bid};
    $seen->{$bid} = 1;
    return 1 if get_id($a) == get_id($b);
    given( $bref ) {
        when(/^(ARRAY|GServ::Array)$/) {
            for my $obj (@$b) {
                return 1 if( a_child_of_b( $a, $obj ) );
            }
        }
        when(/^(HASH|GServ::Hash)$/) {
            for my $obj (values %$b) {
                return 1 if( a_child_of_b( $a, $obj ) );
            }            
        }
        default {
            for my $obj (values %{$b->{DATA}}) {
                return 1 if( a_child_of_b( $a, xform_out( $obj ) ) );
            }                        
        }
    }
    return 0;
} #a_child_of_b

sub stow_all {
    my( @objs ) = values %{$GServ::ObjProvider::DIRTY};
    for my $obj (@objs) {
        stow( $obj );
    }
} #stow_all

sub stow {
    my( $obj ) = @_;
    my $class = ref( $obj );
    return unless $class;
    my $id = get_id( $obj );
    die unless $id;
    given( $class ) {
        when('ARRAY') {
            my $tied = tied @$obj;
            if( $tied ) {
                my( $id, @rest ) = @$tied;
                GServ::ObjIO::stow( $id,'ARRAY',\@rest );
            } else {
                die;
            }
            clean( $id );
        }
        when('HASH') {
            my $tied = tied %$obj;
            if( $tied ) {
                GServ::ObjIO::stow( $id,'HASH',$tied );
            } else {
                die;
            }
            clean( $id );
        }
        when('GServ::Array') {
            if( is_dirty( $id ) ) {
                my( $id, @rest ) = @$obj;
                GServ::ObjIO::stow( $id,'ARRAY',\@rest );
                clean( $id );
            }
            my( $id, @rest ) = @$obj;
            for my $child (map { xform_out( $_ ) } @rest) {
                stow( $child );
            }
        }
        when('GServ::Hash') {
            if( is_dirty( $id ) ) {
                GServ::ObjIO::stow( $id, 'HASH', $obj );
            }
            clean( $id );
            for my $child (map { xform_out( $_ ) } values %$obj) {
                stow( $child );
            }
        }
        default {
            if( is_dirty( $id ) ) {
                GServ::ObjIO::stow( $id, $class, $obj->{DATA} );
                clean( $id );
            }
            for my $child (map { xform_out( $_ ) } values %{$obj->{DATA}}) {
                stow( $child );
            }
        }
    } #given
    
} #stow

sub xform_out {
    my $val = shift;
    return undef unless defined( $val );
    if( index($val,'v') == 0 ) {
        return substr( $val, 1 );
    }
    my $x = fetch( $val );
    return $x;
    return fetch( $val );
}

sub xform_in {
    my $val = shift;
    if( ref( $val ) ) {
        return get_id( $val );
    }
    return "v$val";
}

sub dirty {
    my $obj = shift;
    my $id = shift;
    $GServ::ObjProvider::DIRTY->{$id} = $obj;
}

sub is_dirty {
    my $id = shift;
    return $GServ::ObjProvider::DIRTY->{$id};
}

sub clean {
    my $id = shift;
    delete $GServ::ObjProvider::DIRTY->{$id};
}

1;
__END__

=head1 AUTHOR

Eric Wolf

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2011 Eric Wolf

This module is free software; it can be used under the same terms as perl
itself.

=cut
