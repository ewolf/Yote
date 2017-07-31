package Yote;

use strict;
use warnings;
no  warnings 'uninitialized';

use vars qw($VERSION);

$VERSION = '3.0';

sub open_store {
    my $path = pop;
    my $store = Yote::ObjStore->_new( { store => $path } );
    $store->_init;
    $store;
}

# ---------------------------------------------------------------------------------------------------------------------

package Yote::ObjStore;

use strict;
use warnings;
no warnings 'numeric';
no warnings 'uninitialized';
no warnings 'recursion';

use File::Copy;
use File::Path qw(make_path remove_tree);
use Scalar::Util qw(weaken);

use constant {
    # HASH AND ARRAY
    ID          => 0,
    DATA        => 1,
    DSTORE      => 2,
    LEVEL       => 3,

    # ARRAY
    BLOCK_COUNT => 4,
    BLOCK_SIZE  => 5,
    ITEM_COUNT  => 6,

    # HASH
    BUCKETS => 4,
    SIZE    => 5,
    NEXT    => 6,

};
sub fetch_root {
    my $self = shift;
    die "fetch_root must be called on Yote store object" unless ref( $self );
    my $root = $self->fetch( $self->_first_id );
    unless( $root ) {
        $root = $self->_newroot;
        $root->{ID} = $self->_first_id;
        $self->_stow( $root );
    }
    $root;
} #fetch_root

sub newobj {
    my( $self, $data, $class ) = @_;
    $class ||= 'Yote::Obj';
    $class->_new( $self, $data );
}

sub _newroot {
    my $self = shift;
    Yote::Obj->_new( $self, {}, $self->_first_id );
}

sub copy_from_remote_store {
    my( $self, $obj ) = @_;
    my $r = ref( $obj );
    return $obj unless $r;
    if( $r eq 'ARRAY' ) {
        return [ map { $self->copy_from_remote_store($_) } @$obj ];
    } elsif( $r eq 'HASH' ) {
        return { map { $_ => $self->copy_from_remote_store($obj->{$_}) } keys %$obj };
    } else {
        my $data = { map { $_ => $self->copy_from_remote_store($obj->{DATA}{$_}) } keys %{$obj->{DATA}} };
        return $self->newobj( $data, $r );
    }
}

sub cache_all {
    my $self = shift;
    $self->{CACHE_ALL} = 1;
}

sub uncache {
    my( $self, $obj ) = @_;
    if( ref( $obj ) ) {
        delete $self->{CACHE}{$self->_get_id( $obj )};
    }
}




sub pause_cache {
    my $self = shift;
    $self->{CACHE_ALL} = 0;
}

sub clear_cache {
    my $self = shift;
    $self->{_CACHE} = {};
}


sub fetch {
    my( $self, $id ) = @_;
    return undef unless $id;
    #
    # Return the object if we have a reference to its dirty state.
    #
    my $ref = $self->{_DIRTY}{$id};
    if( defined $ref ) {
        return $ref;
    } else {
        $ref = $self->{_WEAK_REFS}{$id};
        if( $ref ) {
            return $ref;
        }
        undef $ref;
    }
    my $obj_arry = $self->{_YOTEDB}->_fetch( $id );

    if( $obj_arry ) {
        my( $id, $class, $data ) = @$obj_arry;
        if( $class eq 'ARRAY' ) {
            my( @arry );
            tie @arry, 'Yote::Array', $self, $id, @$data;
            $self->_store_weak( $id, \@arry );
            return \@arry;
        }
        elsif( $class eq 'HASH' ) {
            my( %hash );
            tie %hash, 'Yote::Hash', $self, $id, @$data;
            $self->_store_weak( $id, \%hash );
            return \%hash;
        }
        else {
            my $obj;
            eval {
                my $path = $class;
                unless( $INC{ $class } ) {
                    eval("use $class");
                }
                $obj = $self->{_WEAK_REFS}{$id} || $class->_instantiate( $id, $self );
            };
            die $@ if $@;
            $obj->{DATA} = { @$data };
            $obj->{ID} = $id;
            $self->_store_weak( $id, $obj );
            $obj->_load();
            return $obj;
        }
    }
    return undef;
} #fetch

=head2 run_purger

=cut
sub run_purger {
    my( $self, $make_tally, $copy_only ) = @_;
    $self->stow_all();

    my $keep_db = $self->{_YOTEDB}->_generate_keep_db();

    # analyze to see what percentage would be kept
    my $total = $keep_db->entry_count;
    my $keep = 0;
    for my $tid (1..$total) {
        my( $has_keep ) = $keep_db->get_record( $tid )->[0];
        $keep++ if $has_keep;
    }

    #
    # If there are more things to keep than not, do a db purge,
    # otherwise, rebuild the db.
    #
    my $do_purge = $keep > ( $total/2 ) && ! $copy_only;
    my $purged;
    if( $do_purge ) {
        $purged = $self->{_YOTEDB}->_purge_objects( $keep_db, $make_tally );
        $self->{_YOTEDB}->_update_recycle_ids( $keep_db );
        $keep_db->unlink_store;
    } else {
        $purged = $self->_copy_active_ids( $keep_db );
        # keep db is not copied over
    }

    $purged;
} #run_purger

sub _copy_active_ids {
    my( $self, $copy_db ) = @_;
    $self->stow_all();

    my $original_dir = $self->{args}{store};
    my $backdir = $original_dir . '_COMPRESS_BACK_RECENT';
    my $newdir  = $original_dir . '_NEW_RECYC';

    if( -e $backdir ) {
        my $oldback = $original_dir . '_COMPRESS_BACK_OLD';
        if( -d $oldback ) {
            warn "Removing old compression backup directory";
            remove_tree( $oldback );
        }
        move( $backdir, $oldback ) or die $!;
    }

    if( -x $newdir ) {
        die "Unable to run compress store, temp directory '$newdir' already exists.";
    }
    my $newstore = Yote::ObjStore->_new( { store => $newdir } );

    my( @purges );
    for my $keep_id ( 1..$copy_db->entry_count ) {

        my( $has_keep ) = $copy_db->get_record( $keep_id )->[0];
        if( $has_keep ) {
            my $obj = $self->fetch( $keep_id );

            $newstore->{_YOTEDB}{DATA_STORE}->ensure_entry_count( $keep_id - 1 );
            $newstore->_dirty( $obj, $keep_id );
            $newstore->_stow( $obj, $keep_id );
        } elsif( $self->{_YOTEDB}{DATA_STORE}->has_id( $keep_id ) ) {
            push @purges, $keep_id;
        }
    } #each entry id

    # reopen data store
    $self->{_YOTEDB} = Yote::YoteDB->open( $self, $self->{args} );
    move( $original_dir, $backdir ) or die $!;
    move( $newdir, $original_dir ) or die $!;

    \@purges;

} #_copy_active_ids

=head2 has_id

 Returns true if there is a valid reference linked to the id

=cut
sub has_id {
    my( $self, $id ) = @_;
    return $self->{_YOTEDB}{DATA_STORE}->has_id( $id );
}

=head2 stow_all

 Saves all newly created or dirty objects.

=cut
sub stow_all {
    my $self = shift;
    my @odata;
    for my $obj (values %{$self->{_DIRTY}} ) {
        my $cls;
        my $ref = ref( $obj );
        if( $ref eq 'ARRAY' ) {
            $cls = 'ARRAY';
        } elsif( $ref eq 'HASH' ) {
            $cls = 'HASH';
        } else {
            $cls = $ref;
        }
        my( $text_rep ) = $self->_raw_data( $obj );
        push( @odata, [ $self->_get_id( $obj ), $cls, $text_rep ] );
    }
    $self->{_YOTEDB}->_stow_all( \@odata );
    $self->{_DIRTY} = {};
} #stow_all


=head2 stow( $obj )

 Saves that object to the database

=cut
sub stow {
    my( $self, $obj ) = @_;
    my $cls;
    my $ref = ref( $obj );
    if( $ref eq 'ARRAY' || $ref eq 'Yote::Array' ) {
        $cls = 'ARRAY';
    } elsif( $ref eq 'HASH' ) {
        $cls = 'HASH';
    } else {
        $cls = $ref;
    }
    my $id = $self->_get_id( $obj );
    my( $text_rep ) = $self->_raw_data( $obj );
    $self->{_YOTEDB}->_stow( $id, $cls, $text_rep );
    delete $self->{_DIRTY}{$id};
} #stow



# -------------------------------
#      * PRIVATE METHODS *
# -------------------------------
sub _new { #Yote::ObjStore
    my( $pkg, $args ) = @_;
    my $self = bless {
        _DIRTY     => {},
        _WEAK_REFS => {},
        args       => $args,
    }, $pkg;
    $self->{_YOTEDB} = Yote::YoteDB->open( $self, $args );
    $self;
} #_new

sub _init {
    my $self = shift;
    for my $pkg ( qw( Yote::Obj Yote::Array Yote::Hash ) ) {
        $INC{ $pkg } or eval("use $pkg");
    }
    $self->fetch_root;
    $self->stow_all;
    $self;
}


sub dirty_count {
    my $self = shift;
    return scalar( keys %{$self->{_DIRTY}} );
}

#
# Markes given object as dirty.
#
sub _dirty {
    # ( $self, $ref, $id
    $_[0]->{_DIRTY}->{$_[2]} = $_[1];
} #_dirty

#
# Returns the first ID that is associated with the root Root object
#
sub _first_id {
    shift->{_YOTEDB}->_first_id();
} #_first_id

sub _get_id {
    # for debugging I think?
    shift->__get_id( shift );
}

sub __get_id {
    my( $self, $ref ) = @_;

    my $class = ref( $ref );
    die "__get_id requires reference. got '$ref'" unless $class;

    if( $class eq 'Yote::Array') {
        return $ref->[ID];
    }
    elsif( $class eq 'ARRAY' ) {
        my $tied = tied @$ref;
        if( $tied ) {
            $tied->[ID] ||= $self->{_YOTEDB}->_get_id( "ARRAY" );
            return $tied->[ID];
        }
        my( @data ) = @$ref;
        my $id = $self->{_YOTEDB}->_get_id( $class );
        tie @$ref, 'Yote::Array', $self, $id;
        push( @$ref, @data ) if @data;
        $self->_dirty( $ref, $id );
        $self->_store_weak( $id, $ref );
        return $id;
    }
    elsif( $class eq 'Yote::Hash' ) {
        return $ref->[ID];
    }
    elsif( $class eq 'HASH' ) {
        my $tied = tied %$ref;
        if( $tied ) {
            my $useclass = 'HASH';
            $tied->[ID] ||= $self->{_YOTEDB}->_get_id( $useclass );
            return $tied->[ID];
        } else {
            $class = 'Yote::Hash';
        }
        my $id = $self->{_YOTEDB}->_get_id( $class );

        my( %vals ) = %$ref;

        tie %$ref, 'Yote::Hash', $self, $id;
        for my $key (keys %vals) {
            $ref->{$key} = $vals{$key};
        }
        $self->_dirty( $ref, $id );
        $self->_store_weak( $id, $ref );
        return $id;
    }
    else {
        return $ref->{ID} if $ref->{ID};
        if( $class eq 'Yote::Root' ) {
            $ref->{ID} = $self->{_YOTEDB}->_first_id( $class );
        } else {
            $ref->{ID} ||= $self->{_YOTEDB}->_get_id( $class );
        }
        return $ref->{ID};
    }

} #_get_id

sub _stow {
    my( $self, $obj, $id ) = @_;

    my $class = ref( $obj );
    return unless $class;
    $id //= $self->_get_id( $obj );
    die unless $id;

    my( $text_rep, $data ) = $self->_raw_data( $obj );

    if( $class eq 'ARRAY' ) {
        $self->{_YOTEDB}->_stow( $id, 'ARRAY', $text_rep );
        $self->_clean( $id );
    }
    elsif( $class eq 'HASH' ) {
        $self->{_YOTEDB}->_stow( $id, 'HASH', $text_rep );
        $self->_clean( $id );
    }
    elsif( $class eq 'Yote::Array' ) {
        if( $self->_is_dirty( $id ) ) {
            $self->{_YOTEDB}->_stow( $id,'ARRAY',$text_rep );
            $self->_clean( $id );
        }
        for my $child (@$data) {
            if( $child =~ /^[0-9]/ && $self->{_DIRTY}->{$child} ) {
                $self->_stow( $child, $self->{_DIRTY}->{$child} );
            }
        }
    }
    elsif( $class eq 'Yote::Hash' ) {
        if( $self->_is_dirty( $id ) ) {
            $self->{_YOTEDB}->_stow( $id, 'HASH', $text_rep );
        }
        $self->_clean( $id );
        for my $child (values %$data) {
            if( $child =~ /^[0-9]/ && $self->{_DIRTY}->{$child} ) {
                $self->_stow( $child, $self->{_DIRTY}->{$child} );
            }
        }
    }
    else {
        if( $self->_is_dirty( $id ) ) {
            $self->{_YOTEDB}->_stow( $id, $class, $text_rep );
            $self->_clean( $id );
        }
        for my $val (values %$data) {
            if( $val =~ /^[0-9]/ && $self->{_DIRTY}->{$val} ) {
                $self->_stow( $val, $self->{_DIRTY}->{$val} );
            }
        }
    }
    $id;
} #_stow

sub _xform_in {
    my( $self, $val ) = @_;
    if( ref( $val ) ) {
        return $self->_get_id( $val );
    }
    return defined $val ? "v$val" : undef;
}

sub _xform_out {
    my( $self, $val ) = @_;
    return undef unless defined( $val );
    if( index($val,'v') == 0 ) {
        return substr( $val, 1 );
    }
    return $self->fetch( $val );
}

sub _clean {
    my( $self, $id ) = @_;
    delete $self->{_DIRTY}{$id};
} #_clean

sub _is_dirty {
    my( $self, $obj ) = @_;
    my $id = ref($obj) ? _get_id($obj) : $obj;
    my $ans = $self->{_DIRTY}{$id};
    $ans;
} #_is_dirty

#
# Returns data structure representing object. References are integers. Values start with 'v'.
#
sub _raw_data {
    my( $self, $obj ) = @_;
    my $class = ref( $obj );
    return unless $class;
    my $id = $self->_get_id( $obj );
    die unless $id;

    if( $class eq 'ARRAY' || $class eq 'Yote::Array' ) {
        my $tied = $class eq 'ARRAY' ? tied( @$obj ) : $obj;
        my $r = $tied->[ID];
        if( ref( $tied ) eq 'Yote::Array' ) {
            return join( "`", $tied->[LEVEL], $tied->[ITEM_COUNT], $tied->[BLOCK_COUNT], map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } @$r ), $r;
        }
        else {
            die "Unknown class '$class' for yote ARRAY reference. Must be Yote::Array";
        }
    }
    elsif( $class eq 'HASH' || $class eq 'Yote::Hash' ) {
        my $tied = $class eq 'HASH' ? tied( %$obj ) : $obj;
        my $r = $tied->[ID];
        if( ref( $tied ) eq 'Yote::Hash' ) {
            if( $tied->[LEVEL] ) {
                # has an array of buckets rather than a simple hash
                return join( "`", $tied->[LEVEL], $tied->[BUCKETS], $tied->[SIZE], map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } @$r ), $r;
            }
            return join( "`", $tied->[LEVEL], $tied->[BUCKETS], $tied->[SIZE], map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } %$r ), $r;
        }
        else {
            die "Unknown class '$class' for yote HASH reference. Must be Yote::Hash";
        }
    }
    else {
        my $r = $obj->{DATA};
        return join( "`", map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } %$r ), $r;
    }

} #_raw_data


sub _store_weak {
    my( $self, $id, $ref ) = @_;
    die unless $ref;
    $self->{_WEAK_REFS}{$id} = $ref;

    weaken( $self->{_WEAK_REFS}{$id} );
} #_store_weak

# ---------------------------------------------------------------------------------------------------------------------

=head1 NAME

 Yote::Obj - Generic container object for graph.

=head1 DESCRIPTION

A Yote::Obj is a container class that as a specific idiom for getters
and setters. This idiom is set up to avoid confusion and collision
with any method names.

 # sets the 'foo' field to the given value.
 $obj->set_foo( { value => $store->newobj } );

 # returns the value for bar, and if none, sets it to 'default'
 my $bar = $obj->get_bar( "default" );

 $obj->add_to_somelist( "Freddish" );
 my $list = $obj->get_somelist;
 $list->[ 0 ] == "Freddish";


 $obj->remove_from_somelist( "Freddish" );

=cut
package Yote::Obj;

use strict;
use warnings;
no  warnings 'uninitialized';

#
# The string version of the yote object is simply its id. This allows
# objet ids to easily be stored as hash keys.
#
use overload
    '""' => sub { shift->{ID} }, # for hash keys
    eq   => sub { ref($_[1]) && $_[1]->{ID} == $_[0]->{ID} },
    ne   => sub { ! ref($_[1]) || $_[1]->{ID} != $_[0]->{ID} },
    '=='   => sub { ref($_[1]) && $_[1]->{ID} == $_[0]->{ID} },
    '!='   => sub { ! ref($_[1]) || $_[1]->{ID} != $_[0]->{ID} },
    fallback => 1;

=head2 absorb( hashref )

    pulls the hash data into this object.

=cut
sub absorb {
    my( $self, $data ) = @_;
    my $obj_store = $self->{STORE};
    for my $key ( sort keys %$data ) {
        my $item = $data->{ $key };
        $self->{DATA}{$key} = $obj_store->_xform_in( $item );
    }
    $obj_store->_dirty( $self, $self->{ID} );

} #absorb

sub id {
    shift->{ID};
}

=head2 set( $field, $value )

    Assigns the given value to the field in this object and returns the
    assigned value.

=cut
sub set {
    my( $self, $fld, $val ) = @_;

    my $inval = $self->{STORE}->_xform_in( $val );
    if( $self->{DATA}{$fld} ne $inval ) {
        $self->{STORE}->_dirty( $self, $self->{ID} );
    }

    unless( defined $inval ) {
        delete $self->{DATA}{$fld};
        return;
    }
    $self->{DATA}{$fld} = $inval;
    return $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
} #set


=head2 get( $field, $default-value )

    Returns the value assigned to the field, assinging the default
    value to it if the value is currently not defined.

=cut
sub get {
    my( $self, $fld, $default ) = @_;
    my $cur = $self->{DATA}{$fld};
    my $store = $self->{STORE};
    if( ! defined( $cur ) && defined( $default ) ) {
        if( ref( $default ) ) {
            # this must be done to make sure the reference is saved for cases where the reference has not yet made it to the store of things to save
            $store->_dirty( $store->_get_id( $default ) );
        }
        $store->_dirty( $self, $self->{ID} );
        $self->{DATA}{$fld} = $store->_xform_in( $default );
    }
    return $store->_xform_out( $self->{DATA}{$fld} );
} #get


# -----------------------
#
#     Public Methods
# -----------------------
#
# Defines get_foo, set_foo, add_to_list, remove_from_list
#
sub AUTOLOAD {
    my( $s, $arg ) = @_;
    my $func = our $AUTOLOAD;

    if( $func =~/:add_to_(.*)/ ) {
        my( $fld ) = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, @vals ) = @_;
            my $get = "get_$fld";
            my $arry = $self->$get([]); # init array if need be
            push( @$arry, @vals );
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    } #add_to
    elsif( $func =~/:add_once_to_(.*)/ ) {
        my( $fld ) = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, @vals ) = @_;
            my $get = "get_$fld";
            my $arry = $self->$get([]); # init array if need be
            for my $val ( @vals ) {
                unless( grep { $val eq $_ } @$arry ) {
                    push @$arry, $val;
                }
            }
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    } #add_once_to
    elsif( $func =~ /:remove_from_(.*)/ ) { #removes the first instance of the target thing from the list
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, @vals ) = @_;
            my $get = "get_$fld";
            my $arry = $self->$get([]); # init array if need be
            for my $val (@vals ) {
                for my $i (0..$#$arry) {
                    if( $arry->[$i] eq $val ) {
                        splice @$arry, $i, 1;
                        last;
                    }
                }
            }
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    }
    elsif( $func =~ /:remove_all_from_(.*)/ ) { #removes the first instance of the target thing from the list
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, @vals ) = @_;
            my $get = "get_$fld";
            my $arry = $self->$get([]); # init array if need be
            for my $val (@vals) {
                my $count = grep { $_ eq $val } @$arry;
                while( $count ) {
                    for my $i (0..$#$arry) {
                        if( $arry->[$i] eq $val ) {
                            --$count;
                            splice @$arry, $i, 1;
                            last unless $count;
                        }
                    }
                }
            }
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    }
    elsif ( $func =~ /:set_(.*)/ ) {
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, $val ) = @_;
            my $inval = $self->{STORE}->_xform_in( $val );
            $self->{STORE}->_dirty( $self, $self->{ID} ) if $self->{DATA}{$fld} ne $inval;
            unless( defined $inval ) {
                delete $self->{DATA}{$fld};
                return;
            }
            $self->{DATA}{$fld} = $inval;
            return $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
        };
        goto &$AUTOLOAD;
    }
    elsif( $func =~ /:get_(.*)/ ) {
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, $init_val ) = @_;
            if( ! defined( $self->{DATA}{$fld} ) && defined($init_val) ) {
                if( ref( $init_val ) ) {
                    # this must be done to make sure the reference is saved for cases where the reference has not yet made it to the store of things to save
                    $self->{STORE}->_dirty( $init_val, $self->{STORE}->_get_id( $init_val ) );
                }
                $self->{STORE}->_dirty( $self, $self->{ID} );
                $self->{DATA}{$fld} = $self->{STORE}->_xform_in( $init_val );
            }
            return $self->{STORE}->_xform_out( $self->{DATA}{$fld} );
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    }
    else {
        die "Unknown Yote::Obj function '$func'";
    }

} #AUTOLOAD

# -----------------------
#
#     Overridable Methods
# -----------------------

=head2 _init

    This is called the first time an object is created. It is not
    called when the object is loaded from storage. This can be used
    to set up defaults. This is meant to be overridden.

=cut
sub _init {}

=head2 _init

    This is called each time the object is loaded from the data store.
    This is meant to be overridden.

=cut
sub _load {}



# -----------------------
#
#     Private Methods
#
# -----------------------


sub _new { #new Yote::Obj
    my( $pkg, $obj_store, $data, $_id ) = @_;

    my $class = ref($pkg) || $pkg;
    my $obj = bless {
        DATA     => {},
        STORE    => $obj_store,
    }, $class;
    $obj->{ID} = $_id || $obj_store->_get_id( $obj );
    $obj_store->_dirty( $obj, $obj->{ID} );
    $obj->_init(); #called the first time the object is created.

    if( ref( $data ) eq 'HASH' ) {
        $obj->absorb( $data );
    } elsif( $data ) {
        die "Yote::Obj::new must be called with hash or undef. Was called with '". ref( $data ) . "'";
    }
    return $obj;
} #_new

sub _store {
    return shift->{STORE};
}

#
# Called by the object provider; returns a Yote::Obj the object
# provider will stuff data into. Takes the class and id as arguments.
#
sub _instantiate {
    bless { ID => $_[1], DATA => {}, STORE => $_[2] }, $_[0];
} #_instantiate

sub DESTROY {
    my $self = shift;

    delete $self->{STORE}{_WEAK_REFS}{$self->{ID}};
}


# ---------------------------------------------------------------------------------------------------------------------

package Yote::Array;


############################################################################################################
# This module is used transparently by Yote to link arrays into its graph structure. This is not meant to  #
# be called explicitly or modified.                                                                        #
############################################################################################################

use strict;
use warnings;

no warnings 'uninitialized';
use Tie::Array;

$Yote::Array::MAX_BLOCKS = 1_000_000;

use constant {
    ID          => 0,
    DATA        => 1,
    DSTORE      => 2,
    LEVEL       => 3,
    BLOCK_COUNT => 4,
    BLOCK_SIZE  => 5,
    ITEM_COUNT  => 6,
};

sub TIEARRAY {
    my( $class, $obj_store, $id, $level, $item_count, $block_count, @list ) = @_;

    $item_count  ||= 0;
    $level       ||= 0;
    $block_count ||= $Yote::Array::MAX_BLOCKS;
    my $block_size  = $block_count ** $level;

    my $blocks = [@list];

    # once the array is tied, an additional data field will be added
    # so obj will be [ $id, $storage, $obj_store ]
    my $obj = bless [
        $id,
        $blocks,
        $obj_store,
        $level,
        $block_count,
        $block_size,
        $item_count,
    ], $class;
    return $obj;
} #TIEARRAY

sub FETCH {
    my( $self, $idx ) = @_;
    if( $idx >= $self->[ITEM_COUNT] ) {
        return undef;
    }
    if( $self->[LEVEL] == 0 ) {
        return $self->[DSTORE]->_xform_out( $self->[DATA][$idx] );
    }
    my $block = $self->_getblock( int( $idx / $self->[BLOCK_SIZE] ) );
    if( $block ) {
        return $block->[$idx % $self->[BLOCK_SIZE]];
    }
    return undef;
} #FETCH

sub FETCHSIZE {
    shift->[ITEM_COUNT];
}

sub _embiggen {
    my( $self, $size ) = @_;

    while( $size >= $self->[BLOCK_SIZE] * $self->[BLOCK_COUNT] ) {
        my $store = $self->[DSTORE];

        #
        # need to tie a new block, not use _getblock
        # becaues we do squirrely things with its tied guts
        #
        my $newblock = [];
        my $newid = $store->{_YOTEDB}->_get_id( 'Yote::Array' );
        tie @$newblock, 'Yote::Array', $store, $newid, $self->[LEVEL], $self->[BLOCK_COUNT], $self->[BLOCK_COUNT] * $self->[BLOCK_SIZE], $self->[BLOCK_SIZE];
        $store->_store_weak( $newid, $newblock );
        $store->_dirty( $store->{_WEAK_REFS}{$newid}, $newid );

        my $tied = tied @$newblock;
        $tied->[DATA] = $self->[DATA];
        $self->[DATA] = [ $newid ];

        $self->[BLOCK_SIZE] *= $self->[BLOCK_COUNT];
        $self->[LEVEL]++;
        $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );
    }
} #_embiggen

#
# get a block at the given block index. Returns undef
# if there isn't one ther, or creates and returns
# one if passed do create
#
sub _getblock {
    my( $self, $block_idx, $do_create ) = @_;
    
    my $block_id = $self->[DATA][$block_idx];
    my $store = $self->[DSTORE];
    
    if( $block_id ) {
        my $block = $store->fetch( $block_id );
        return wantarray ? ($block, tied @$block) : $block;
    }

    if( $do_create ) {
        $block_id = $store->{_YOTEDB}->_get_id( 'Yote::Array' );
        my $block = [];
        my $level = $self->[LEVEL] - 1;
        tie @$block, 'Yote::Array', $store, $block_id, $level, 0, $self->[BLOCK_COUNT];

        $store->_store_weak( $block_id, $block );
        $store->_dirty( $store->{_WEAK_REFS}{$block_id}, $block_id );
        $self->[DATA][$block_idx] = $block_id;
        return wantarray ? ($block, tied @$block) : $block;
    }
    return undef;
} #_getblock

sub STORE {
    my( $self, $idx, $val ) = @_;

    if( $idx > $self->[BLOCK_COUNT]*$self->[BLOCK_SIZE] ) {
        $self->_embiggen( $idx );
        $self->STORE( $idx, $val );
        return;
    }
    
    if( $idx >= $self->[ITEM_COUNT] ) {
        $self->[ITEM_COUNT] = $idx - 1;
        my $store = $self->[DSTORE];
        $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );
    }

    if( $self->[LEVEL] == 0 ) {
        $self->[DATA][$idx] = $self->[DSTORE]->_xform_in( $val );
        return;
    }

    my $block = $self->_getblock( int( $idx / $self->[BLOCK_SIZE] ), 'CREATE' );
    $block->[$idx % $self->[BLOCK_SIZE]] = $val;

} #STORE

sub STORESIZE {
    my( $self, $size ) = @_;

    $size = 0 if $size < 0;

    # fixes the size of the array if the array were to shrink
    my $current_oversize = $self->[ITEM_COUNT] - $size;
    if( $current_oversize > 0 ) {
        $self->SPLICE( $size, $current_oversize );
    } #if the array shrinks

} #STORESIZE

sub EXISTS {
    my( $self, $idx ) = @_;
    if( $idx >= $self->[ITEM_COUNT] ) {
        return 0;
    }
    if( $self->[LEVEL] == 0 ) {
        return exists $self->[DATA][$idx];
    }
    my $block = $self->_getblock( int( $idx / $self->[BLOCK_SIZE] ) );
    return $block && exists $block->[$idx % $self->[BLOCK_SIZE]];
} #EXISTS

sub DELETE {
    my( $self, $idx ) = @_;
    if( $idx >= $self->[ITEM_COUNT] ) {
        return undef;
    }

    # if the last one was removed, shrink until there is a
    # defined value
    if( $idx == $self->[ITEM_COUNT] - 1 ) {
        $self->[ITEM_COUNT]--;
        while( ! $self->EXISTS( $self->[ITEM_COUNT] - 1 ) ) {
            $self->[ITEM_COUNT]--;
        }
        $self->[DSTORE]->_dirty( $self->[DSTORE]->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );
    }
    
    if( $self->[LEVEL] == 0 ) {
        return $self->[DSTORE]->_xform_out( delete $self->[DATA][$idx] );
    }

    my $block = $self->_getblock( int( $idx / $self->[BLOCK_SIZE] ) );
    if( $block ) {
        return delete $block->[ $idx % $self->[BLOCK_SIZE] ];
    }
} #DELETE

sub CLEAR {
    my $self = shift;
    $self->[ITEM_COUNT] = 0;
    $self->[DATA] = [];
    $self->[DSTORE]->_dirty( $self->[DSTORE]->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );
}
sub PUSH {
    my( $self, @vals ) = @_;
    return unless @vals;

    $self->SPLICE( $self->[ITEM_COUNT], 0, @vals );
}
sub POP {
    my $self = shift;
    return undef unless $self->[ITEM_COUNT];
    return $self->DELETE( $self->[ITEM_COUNT] - 1 );
}
sub SHIFT {
    my( $self ) = @_;
    return undef unless $self->[ITEM_COUNT];
    return $self->SPLICE( 0, 1 );
}

sub UNSHIFT {
    my( $self, @vals ) = @_;
    return unless @vals;
    return $self->SPLICE( 0, 0, @vals );
}


sub SPLICE {
    my( $self, $offset, $remove_length, @vals ) = @_;

    # if negative, the offset is from the end
    if( $offset < 0 ) {
        $offset = $self->[ITEM_COUNT] + $offset;
    }

    # if negative, remove everything except the abs($remove_length) at
    # the end of the list
    if( $remove_length < 0 ) {
        $remove_length = ($self->[ITEM_COUNT] - $offset) + $remove_length;
    }

    #
    # embiggen to delta size if this would grow
    #
    my $delta = @vals - $remove_length;
    return undef if $delta == 0;
    if( $delta > 0 ) {
        $self->_embiggen( $self->[ITEM_COUNT] + $delta );
    }

    my $store = $self->[DSTORE];
    
    $self->[ITEM_COUNT] += $delta;
    $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );

    if( $self->[LEVEL] == 0 ) {
        my @removed = splice @{$self->[DATA]}, $offset, $remove_length, map { $store->_xform_in( $_ ) } @vals;
        return map { $store->_xform_out($_) } @removed;
    }
    
    my @removed;

    my $block_idx = int( $offset / $self->[BLOCK_SIZE] );
    my $block_offset = $offset % $self->[BLOCK_SIZE];
    
    my $vacuum = 0; # how much one block needs to draw from subsequent blocks
    my $prev_block;
    
    while( $block_idx < $self->[BLOCK_COUNT] && ($remove_length || @vals ) ) {
        my $block = $self->_getblock( $block_idx, "CREATE" );

        my $block_space_after_offset = $#$block - $block_offset;

        if( $vacuum > 0 ) {
            push @$prev_block, splice( @$block, 0, $block_space_after_offset );
            $vacuum = 0;
            undef $prev_block;
        }
            
        #
        # remove what you can from this block
        #
        if( $block_offset == 0 && $remove_length >= $self->[BLOCK_SIZE] ) {
            #
            # Remove block entirely as the remove length is larger than it
            #
            splice @{$self->[DATA]}, $block_offset, 1;
            $remove_length -= $self->[BLOCK_SIZE];
        }
        elsif( $remove_length > $block_space_after_offset ) {
            #
            # Remove the rest of the block
            #
            push @removed, splice( @$block, $block_offset, $block_space_after_offset );
            $remove_length -= $block_space_after_offset;
        }
        else {
            #
            # Remove remove_length from the block
            #
            push @removed, splice( @$block, $block_offset, $remove_length );
            $remove_length = 0;
        }

        #
        # check how much room the block has now to put the vals onto it
        #
        my $fillable_room = $self->[BLOCK_SIZE] - $block_offset;
        
        if( @vals > $fillable_room ) {
            push @$block, splice( @vals, 0, $fillable_room );
        } else {
            $vacuum = $fillable_room - @vals;
            $prev_block = $block;
            if( @vals ) {
                push @$block, @vals;
                @vals = ();
            }
        }

        # move on to the start of the next block
        $block_idx++;
        $block_offset = 0;
    } #splicy loop
    
    return @removed;
} #SPLICE

sub EXTEND {
}

sub DESTROY {
    my $self = shift;
    delete $self->[DSTORE]->{_WEAK_REFS}{$self->[ID]};
}

# ---------------------------------------------------------------------------------------

package Yote::Hash;

######################################################################################
# This module is used transparently by Yote to link hashes into its graph structure. #
# This is not meant to  be called explicitly or modified.                            #
######################################################################################

use strict;
use warnings;

no warnings 'uninitialized';
no warnings 'numeric';

use Tie::Hash;

$Yote::Hash::SIZE = 977;

use constant {
    ID          => 0,
    DATA        => 1,
    DSTORE      => 2,
    LEVEL       => 3,
    BUCKETS     => 4,
    SIZE        => 5,
    NEXT        => 6,
};


sub TIEHASH {
    my( $class, $obj_store, $id, $level, $buckets, $size, @fetch_buckets ) = @_;
    $level ||= 0;
    $size  ||= 0;
    $buckets ||= $Yote::Hash::SIZE;
    bless [ $id, $level ? \@fetch_buckets : {@fetch_buckets}, $obj_store, $level, $buckets, $size, [undef,undef,undef] ], $class;
}

sub CLEAR {
    my $self = shift;
    if( $self->[SIZE] > 0 ) {
        $self->[SIZE] = 0;
        my $store = $self->[DSTORE];
        $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );
        %{$self->[DATA]} = ();
    }
}

sub DELETE {
    my( $self, $key ) = @_;

    return undef unless $self->EXISTS( $key );

    $self->[SIZE]--;

    my $data = $self->[DATA];
    my $store = $self->[DSTORE];

    if( $self->[LEVEL] == 0 ) {
        $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );
        return $store->_xform_out( delete $data->{$key} );
    } else {
        my $hval = 0;
        foreach (split //,$key) {
            $hval = $hval*33 - ord($_);
        }
        $hval = $hval % $self->[BUCKETS];
        return $self->[DSTORE]->fetch( $data->[$hval] )->DELETE( $key );
    }
    return undef;
} #DELETE


sub EXISTS {
    my( $self, $key ) = @_;

    if( $self->[LEVEL] == 0 ) {
        return exists $self->[DATA]{$key};
    } else {
        my $data = $self->[DATA];
        my $hval = 0;
        foreach (split //,$key) {
            $hval = $hval*33 - ord($_);
        }
        $hval = $hval % $self->[BUCKETS];
        my $hash_id = $data->[$hval];
        if( $hash_id ) {
            my $hash = $self->[DSTORE]->fetch( $hash_id );
            my $tied = tied %$hash;
            return $tied->EXISTS( $key );
        }

    }
    return 0;
} #EXISTS

sub FETCH {
    my( $self, $key ) = @_;
    my $data = $self->[DATA];

    if( $self->[LEVEL] == 0 ) {
        return $self->[DSTORE]->_xform_out( $data->{$key} );
    } else {
        my $hval = 0;
        foreach (split //,$key) {
            $hval = $hval*33 - ord($_);
        }
        $hval = $hval % $self->[BUCKETS];
        my $hash_id = $data->[$hval];
        if( $hash_id ) {
            my $hash = $self->[DSTORE]->fetch( $hash_id );
            my $tied = tied %$hash;
            return $tied->FETCH( $key );
        }
    }
    return undef;
} #FETCH


sub STORE {
    my( $self, $key, $val ) = @_;

    my $data = $self->[DATA];

    #
    # EMBIGGEN TEST
    #
    my $newkey = ! $self->EXISTS( $key );
    if( $newkey ) {
        $self->[SIZE]++;
    }

    if( $self->[LEVEL] == 0 ) {
        $data->{$key} = $self->[DSTORE]->_xform_in( $val );

        if( $self->[SIZE] > $self->[BUCKETS] ) {

            # do the thing converting this to a deeper level
            $self->[LEVEL] = 1;
            my $store = $self->[DSTORE];
            my $yotedb = $store->{_YOTEDB};
            my( @newhash, @newids );

            for my $key (keys %$data) {
                my $hval = 0;
                foreach (split //,$key) {
                    $hval = $hval*33 - ord($_);
                }
                $hval = $hval % $self->[BUCKETS];

                my $hash = $newhash[$hval];
                if( $hash ) {
                    my $tied = tied %$hash;
                    $tied->STORE( $key, $store->_xform_out($data->{$key}) );
                } else {
                    $hash = {};
                    my $hash_id = $yotedb->_get_id( 'Yote::Hash' );
                    tie %$hash, 'Yote::Hash', $store, $hash_id, 0, $self->[BUCKETS]+1, 1, $key, $data->{$key};

                    $store->_store_weak( $hash_id, $hash );
                    $store->_dirty( $store->{_WEAK_REFS}{$hash_id}, $hash_id );

                    $newhash[$hval] = $hash;
                    $newids[$hval] = $hash_id;
                }

            }
            $self->[DATA] = \@newids;
            $data = $self->[DATA];

            $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );

        } # EMBIGGEN CHECK

    } else {
        my $store = $self->[DSTORE];
        my $hval = 0;
        foreach (split //,$key) {
            $hval = $hval*33 - ord($_);
        }
        $hval = $hval % $self->[BUCKETS];
        my $hash_id = $data->[$hval];
        my $hash;
        if( $hash_id ) {
            $hash = $store->fetch( $hash_id );
            my $tied = tied %$hash;
            $tied->STORE( $key, $val );
        } else {
            $hash = {};
            $hash_id = $store->{_YOTEDB}->_get_id( 'Yote::Hash' );
            tie %$hash, 'Yote::Hash', $store, $hash_id, 0, $self->[BUCKETS]+1, 1, $key, $store->_xform_in( $val );
            $store->_store_weak( $hash_id, $hash );
            $store->_dirty( $store->{_WEAK_REFS}{$hash_id}, $hash_id );
            $data->[$hval] = $hash_id;
        }
    }

} #STORE

sub FIRSTKEY {
    my $self = shift;

    my $data = $self->[DATA];
    if( $self->[LEVEL] == 0 ) {
        my $a = scalar keys %$data; #reset
        my( $k, $val ) = each %$data;
        return wantarray ? ( $k => $self->[DSTORE]->_xform_out( $val ) ) : $k;
    }
    $self->[NEXT] = [undef,undef,undef];
    return $self->NEXTKEY;
}

sub NEXTKEY  {
    my $self = shift;
    my $data = $self->[DATA];
    if( $self->[LEVEL] == 0 ) {
        my( $k, $val ) = each %$data;
        return wantarray ? ( $k => $self->[DSTORE]->_xform_out($val) ) : $k;
    } else {
        my $store = $self->[DSTORE];
        do {
            my $nexthashid = $data->[$self->[NEXT][0]||0];
            if( $nexthashid ) {
                my $hash = $self->[NEXT][2] || $store->fetch( $nexthashid );
                my $tied = tied %$hash;

                my( $k, $v ) = $self->[NEXT][1] ? $tied->NEXTKEY : $tied->FIRSTKEY;
                if( defined( $k ) ) {
                    $self->[NEXT][1] = 1;
                    $self->[NEXT][2] = $hash;
                    return wantarray ? ( $k => $v ) : $k;
                }
            }
            $self->[NEXT][0]++;
            $self->[NEXT][1] = 0;
            $self->[NEXT][2] = undef;
        } while( $self->[NEXT][0] < @$data );
    }
    $self->[NEXT] = [undef,undef,undef];
    return undef;

} #NEXTKEY



sub DESTROY {
    my $self = shift;

    #remove all WEAK_REFS to the buckets
    undef $self->[DATA];

    delete $self->[DSTORE]->{_WEAK_REFS}{$self->[ID]};
}

# ---------------------------------------------------------------------------------------

package Yote::YoteDB;

use strict;
use warnings;

no warnings 'uninitialized';

use Data::RecordStore;

use File::Path qw(make_path);

use constant {
   CLS => 1,
  DATA => 2,
};

#
# This the main index and stores in which table and position
# in that table that this object lives.
#
sub open {
  my( $pkg, $obj_store, $args ) = @_;
  my $class = ref( $pkg ) || $pkg;

  my $DATA_STORE;
  eval {
      $DATA_STORE = Data::RecordStore->open( $args->{ store } );
  };
  if( $@ ) {
      if( $@ =~ /old format/ ) {
          die "This yote store is of an older format. It can be converted using the yote_explorer";
      }
      die $@;
  }
  my $self = bless {
      args       => $args,
      OBJ_STORE  => $obj_store,
      DATA_STORE => $DATA_STORE,
  }, $class;
  $self->{DATA_STORE}->ensure_entry_count( 1 );
  $self;
} #open

#
# Return a list reference containing [ id, class, data ] that
# corresponds to the $id argument. This is used by Yote::ObjStore
# to build the yote object.
#
sub _fetch {
  my( $self, $id ) = @_;
  my $data = $self->{DATA_STORE}->fetch( $id );

  return undef unless $data;

  my $pos = index( $data, ' ' ); #there is a always a space after the class.
  $pos = ( length( $data ) ) if $pos == -1;
  die "Malformed record '$data'" if $pos == -1;
  my $class = substr $data, 0, $pos;
  my $val   = substr $data, $pos + 1;
  my $ret = [$id,$class,$val];

  # so foo` or foo\\` but not foo\\\`
  # also this will never start with a `
  my $parts = [ split /\`/, $val, -1 ];

  # check to see if any of the parts were split on escapes
  # like  mypart`foo`oo (should be translated to mypart\`foo\`oo
  if( 0 < grep { /\\$/ } @$parts ) {
      my $newparts = [];

      my $is_hanging = 0;
      my $working_part = '';

      for my $part (@$parts) {

          # if the part ends in a hanging escape
          if( $part =~ /(^|[^\\])((\\\\)+)?[\\]$/ ) {
              if( $is_hanging ) {
                  $working_part .= "`$part";
              } else {
                  $working_part = $part;
              }
              $is_hanging = 1;
          } elsif( $is_hanging ) {
              my $newpart = "$working_part`$part";
              $newpart =~ s/\\`/`/gs;
              $newpart =~ s/\\\\/\\/gs;
              push @$newparts, $newpart;
              $is_hanging = 0;
          } else {
              # normal part
              push @$newparts, $part;
          }
      }
      if( $is_hanging ) {
          die "Error in parsing parts\n";
      }
      $parts = $newparts;
  }

  $ret->[DATA] = $parts;

  $ret;
} #_fetch

#
# The first object in a yote data store can trace a reference to
# all active objects.
#
sub _first_id {
  return 1;
} #_first_id

#
# Create a new object id and return it.
#
sub _get_id {
  my $self = shift;
  $self->{DATA_STORE}->next_id;
} #_get_id


# used for debugging and testing
sub _max_id {
  shift->{DATA_STORE}->entry_count;
}

sub _generate_keep_db {
    my $self = shift;
    my $mark_to_keep_store = Data::RecordStore::FixedStore->open( "I", $self->{args}{store} . '/PURGE_KEEP' );

    $mark_to_keep_store->empty();
    $mark_to_keep_store->ensure_entry_count( $self->{DATA_STORE}->entry_count );

    my $check_store = Data::RecordStore::FixedStore->open( "L", $self->{args}{store} . '/CHECK' );
    $check_store->empty();

    $mark_to_keep_store->put_record( 1, [ 1 ] );

    my( %seen );
    my( @checks ) = ( 1 );

    for my $referenced_id ( grep { $_ != 1 } grep { defined($self->{OBJ_STORE}{_WEAK_REFS}{$_}) } keys %{ $self->{OBJ_STORE}{_WEAK_REFS} } ) {
        push @checks, $referenced_id;
    }

    #
    # While there are items to check, check them.
    #
    while( @checks || $check_store->entry_count > 0 ) {
        my $check_id = shift( @checks ) || $check_store->pop->[0];
        $mark_to_keep_store->put_record( $check_id, [ 1 ] );

        my $obj_arry = $self->_fetch( $check_id );
        $seen{$check_id} = 1;
        my( @additions );

        if( $obj_arry->[CLS] eq 'Yote::Hash' ) {
            my $level = shift @{$obj_arry->[DATA]}; #remove the level
            shift @{$obj_arry->[DATA]}; #remove the buckets
            shift @{$obj_arry->[DATA]}; #remove the size
            if( $level ) {
                ( @additions ) = grep { /^[^v]/ && ! $seen{$_}++ } @{$obj_arry->[DATA]};
            }
            else {
                my $d = { @{$obj_arry->[DATA]} };
                ( @additions ) = grep { /^[^v]/ && ! $seen{$_}++ } values %$d;
            }
        }
        elsif ( $obj_arry->[CLS] eq 'Yote::Array' ) {
            shift @{$obj_arry->[DATA]}; #item_count
            shift @{$obj_arry->[DATA]}; #block_count
            shift @{$obj_arry->[DATA]}; #block_size
            shift @{$obj_arry->[DATA]}; #level
            ( @additions ) = grep { /^[^v]/ && ! $seen{$_}++ } @{$obj_arry->[DATA]};
        }
        elsif ( ref( $obj_arry->[DATA] ) eq 'ARRAY' ) {
            ( @additions ) = grep { /^[^v]/ && ! $seen{$_}++ } @{$obj_arry->[DATA]};
        }
        else { # Yote::Obj
            ( @additions ) = grep { /^[^v]/ && ! $seen{$_}++ } values %{$obj_arry->[DATA]};
        }
        if( @checks > 1_000_000 ) {
            for my $cid (@checks) {
                my( $has_keep ) = $mark_to_keep_store->get_record( $cid )->[0];
                unless( $has_keep ) {
                    $check_store->push( [ $cid ] );
                }
            }
            splice @checks;
        }
        if( scalar( keys(%seen) ) > 1_000_000 ) {
            %seen = ();
        }
        push @checks, @additions;
    }
    $check_store->unlink_store;

    $mark_to_keep_store;

} #_generate_keep_db

#
# Checks to see if the last entries of the stores can be popped off, making the purging quicker
#
sub _truncate_dbs {
    my( $self, $mark_to_keep_store, $keep_tally ) = @_;
    #loop through each database
    my $stores = $self->{DATA_STORE}->all_stores;
    my( @purged );
    for my $store (@$stores) {
        my $fn = $store->{FILENAME}; $fn =~ s!/[^/]+$!!;
        my $keep;
        while( ! $keep && $store->entry_count ) {
            my( $check_id ) = @{ $store->get_record($store->entry_count) };
            ( $keep ) = $mark_to_keep_store->get_record( $check_id )->[0];
            if( ! $keep ) {
                if( $self->{DATA_STORE}->delete( $check_id ) ) {
                    if( $keep_tally ) {
                        push @purged, $check_id;
                    }
                    $mark_to_keep_store->put_record( $check_id, [ 2 ] ); #mark as already removed by truncate
                }
            }
        }
    }
    \@purged;
}


sub _update_recycle_ids {
    my( $self, $mark_to_keep_store ) = @_;

    return unless $mark_to_keep_store->entry_count > 0;

    my $store = $self->{DATA_STORE};


    # find the higest still existing ID and cap the index to this
    my $highest_keep_id;
    for my $cand (reverse ( 1..$mark_to_keep_store->entry_count )) {
        my( $keep ) = $mark_to_keep_store->get_record( $cand )->[0];
        if( $keep ) {
            $store->set_entry_count( $cand );
            $highest_keep_id = $cand;
            last;
        }
    }

    $store->empty_recycler;

    # iterate each id in the entire object store and add those
    # not marked for keeping into the recycling
    for my $cand (reverse( 1.. $highest_keep_id) ) {
        my( $keep ) = $mark_to_keep_store->get_record( $cand )->[0];
        unless( $keep ) {
            $store->recycle( $cand );
        }
    }
} #_update_recycle_ids


sub _purge_objects {
  my( $self, $mark_to_keep_store, $keep_tally ) = @_;

  my $purged = $self->_truncate_dbs( $mark_to_keep_store );

  for my $cand ( 1..$mark_to_keep_store->entry_count) { #iterate each id in the entire object store
    my( $keep ) = $mark_to_keep_store->get_record( $cand )->[0];

    die "Tried to purge root entry" if $cand == 1 && ! $keep;
    if ( ! $keep ) {
        if( $self->{DATA_STORE}->delete( $cand ) ) {
            $mark_to_keep_store->put_record( $cand, [ 3 ] ); #mark as already removed by purge
            if( $keep_tally ) {
                push @$purged, $cand;
            }
        }
    }
  }

  $purged;

} #_purge_objects


#
# Saves the object data for object $id to the data store.
#
sub _stow { #Yote::YoteDB::_stow
  my( $self, $id, $class, $data ) = @_;
  my $save_data = "$class $data";
  $self->{DATA_STORE}->stow( $save_data, $id );
} #_stow

#
# Takes a list of object data references and stows them all in the datastore.
# returns how many are stowed.
#
sub _stow_all {
  my( $self, $objs ) = @_;
  my $count = 0;
  for my $o ( @$objs ) {
    $count += $self->_stow( @$o );
  }
  return $count;
} #_stow_all

1;

__END__

=head1 NAME

Yote - Persistant Perl container objects in a directed graph of lazilly loaded nodes.

=head1 DESCRIPTION

This is for anyone who wants to store arbitrary structured state data and doesn't have
the time or inclination to write a schema or configure some framework. This can be used
orthagonally to any other storage system.

Yote only loads data as it needs too. It does not load all stored containers at once.
Data is stored in a data directory and is stored using the Data::RecordStore module. A Yote
container is a key/value store where the values can be strings, numbers, arrays, hashes
or other Yote containers.

The entry point for all Yote data stores is the root node. All objects in the store are
unreachable if they cannot trace a reference path back to this node. If they cannot, running
compress_store will remove them.

There are lots of potential uses for Yote, and a few come to mind :

 * configuration data
 * data modeling
 * user preference data
 * user account data
 * game data
 * shopping carts
 * product information

=head1 SYNOPSIS

 use Yote;

 my $store = Yote::open_store( '/path/to/data-directory' );

 my $root_node = $store->fetch_root;

 $root_node->add_to_myList( $store->newobj( {
    someval  => 123.53,
    somehash => { A => 1 },
    someobj  => $store->newobj( { foo => "Bar" },
                'Optional-Yote-Subclass-Package' );
 } );

 # the root node now has a list 'myList' attached to it with the single
 # value of a yote object that yote object has two fields,
 # one of which is an other yote object.

 $root_node->add_to_myList( 42 );

 #
 # New Yote container objects are created with $store->newobj. Note that
 # they must find a reference path to the root to be protected from
 # being deleted from the record store upon compression.
 #
 my $newObj = $store->newobj;

 $root_node->set_field( "Value" );

 my $val = $root_node->get_value( "default" );
 # $val eq 'default'

 $val = $root_node->get_value( "Somethign Else" );
 # $val eq 'default' (old value not overridden by a new default value)


 my $otherval = $root_node->get( 'ot3rv@l', 'other default' );
 # $otherval eq 'other default'

 $root_node->set( 'ot3rv@l', 'newy valuye' );
 $otherval2 = $root_node->get( 'ot3rv@l', 'yet other default' );
 # $otherval2 eq 'newy valuye'

 $root_node->set_value( "Something Else" );

 my $val = $root_node->get_value( "default" );
 # $val eq 'Something Else'

 my $myList = $root_node->get_myList;

 for my $example (@$myList) {
    print ">$example\n";
 }

 #
 # Each object gets a unique ID which can be used to fetch that
 # object directly from the store.
 #
 my $someid = $root_node->get_someobj->{ID};

 my $someref = $store->fetch( $someid );

 #
 # Even hashes and array have unique yote IDS. These can be
 # determined by calling the _get_id method of the store.
 #
 my $hash = $root_node->set_ahash( { zoo => "Zar" } );
 my $hash_id = $store->_get_id( $hash );
 my $other_ref_to_hash = $store->fetch( $hash_id );

 #
 # Anything that cannot trace a reference path to the root
 # is eligable for being removed upon compression.
 #

=head1 PUBLIC METHODS

=head2 open_store( '/path/to/directory' )

Starts up a persistance engine and returns it.

=head1 NAME

 Yote::ObjStore - manages Yote::Obj objects in a graph.

=head1 DESCRIPTION

The Yote::ObjStore does the following things :

 * fetches the root object
 * creates new objects
 * fetches existing objects by id
 * saves all new or changed objects
 * finds objects that cannot connect to the root node and removes them

=head2 fetch_root

 Returns the root node of the graph. All things that can be
trace a reference path back to the root node are considered active
and are not removed when the object store is compressed.

=cut

=head2 newobj( { ... data .... }, optionalClass )

 Creates a container object initialized with the
 incoming hash ref data. The class of the object must be either
 Yote::Obj or a subclass of it. Yote::Obj is the default.

 Once created, the object will be saved in the data store when
 $store->stow_all has been called.  If the object is not attached
 to the root or an object that can be reached by the root, it will be
 remove when Yote::ObjStore::Compress is called.

=head2 copy_from_remote_store( $obj )

 This takes an object that belongs to a seperate store and makes
 a deep copy of it.

=head2 cache_all()

 This turns on caching for the store. Any objects loaded will
 remain cached until clear_cache is called. Normally, they
 would be DESTROYed once their last reference was removed unless
 they are in a state that needs stowing.

=head2 uncache( obj )

  This removes the object from the cache if it was in the cache

=head2 pause_cache()

 When called, no new objects will be added to the cache until
 cache_all is called.

=head2 clear_cache()

 When called, this dumps the object cache. Objects that
 references or have changes that need to be stowed will
 not be cleared.

=cut
=head2 fetch( $id )

 Returns the object with the given id.

=cut


=head1 AUTHOR
       Eric Wolf        coyocanid@gmail.com

=head1 COPYRIGHT AND LICENSE

       Copyright (c) 2017 Eric Wolf. All rights reserved.  This program is free software; you can redistribute it and/or modify it
       under the same terms as Perl itself.

=head1 VERSION
       Version 2.03  (September, 2017))

=cut
