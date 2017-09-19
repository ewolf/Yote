package Yote;

use strict;
use warnings;
no  warnings 'uninitialized';

use vars qw($VERSION);

$VERSION = '2.01';

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

=cut


=head2 open_store( '/path/to/directory' )

Starts up a persistance engine and returns it.

=cut

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

use Module::Loaded;

=head1 NAME

 Yote::ObjStore - manages Yote::Obj objects in a graph.

=head1 DESCRIPTION

The Yote::ObjStore does the following things :

 * fetches the root object
 * creates new objects
 * fetches existing objects by id
 * saves all new or changed objects
 * finds objects that cannot connect to the root node and removes them

=cut

# ------------------------------------------------------------------------------------------
#      * PUBLIC CLASS METHODS *
# ------------------------------------------------------------------------------------------

=head2 fetch_root

 Returns the root node of the graph. All things that can be
trace a reference path back to the root node are considered active
and are not removed when the object store is compressed.

=cut
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

=head2 newobj( { ... data .... }, optionalClass )

 Creates a container object initialized with the
 incoming hash ref data. The class of the object must be either
 Yote::Obj or a subclass of it. Yote::Obj is the default.

 Once created, the object will be saved in the data store when
 $store->stow_all has been called.  If the object is not attached
 to the root or an object that can be reached by the root, it will be
 remove when Yote::ObjStore::Compress is called.

=cut
sub newobj {
    my( $self, $data, $class ) = @_;
    $class ||= 'Yote::Obj';
    $class->_new( $self, $data );
}

sub _newroot {
    my $self = shift;
    Yote::Obj->_new( $self, {}, $self->_first_id );
}

=head2 copy_from_remote_store( $obj )

 This takes an object that belongs to a seperate store and makes
 a deep copy of it.

=cut
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

=head2 cache_all()

 This turns on caching for the store. Any objects loaded will
 remain cached until clear_cache is called. Normally, they
 would be DESTROYed once their last reference was removed unless
 they are in a state that needs stowing.

=cut
sub cache_all {
    my $self = shift;
    $self->{CACHE_ALL} = 1;
}

=head2 uncache( obj )

  This removes the object from the cache if it was in the cache

=cut
sub uncache {
    my( $self, $obj ) = @_;
    if( ref( $obj ) ) {
        delete $self->{CACHE}{$self->_get_id( $obj )};
    }
}



=head2 pause_cache()

 When called, no new objects will be added to the cache until
 cache_all is called.

=cut
sub pause_cache {
    my $self = shift;
    $self->{CACHE_ALL} = 0;
}

=head2 clear_cache()

 When called, this dumps the object cache. Objects that
 references or have changes that need to be stowed will
 not be cleared.

=cut
sub clear_cache {
    my $self = shift;
    $self->{_CACHE} = {};
}



=head2 fetch( $id )

 Returns the object with the given id.

=cut
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
    my $obj_arry = $self->{_DATASTORE}->_fetch( $id );

    if( $obj_arry ) {
        my( $id, $class, $data ) = @$obj_arry;
        if( $class eq 'ARRAY' ) {
            my( @arry );
            tie @arry, 'Yote::Array', $self, $id, @$data;
            $self->_store_weak( $id, \@arry );
            return \@arry;
        }
        elsif( $class eq 'Yote::ArrayGatekeeper' ) {
            my( @arry );
            tie @arry, 'Yote::ArrayGatekeeper', $self, $id, @$data;
            $self->_store_weak( $id, \@arry );
            return \@arry;
        }
        elsif( $class eq 'HASH' ) {
            my( %hash );
            tie %hash, 'Yote::Hash', $self, $id, @$data;
            $self->_store_weak( $id, \%hash );
            return \%hash;
        }
        elsif( $class eq 'Yote::BigHash' ) {
            my( %hash );
            tie %hash, 'Yote::BigHash', $self, $id, @$data;
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
            $obj->{DATA} = $data;
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

    my $keep_db = $self->{_DATASTORE}->_generate_keep_db();

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
        $purged = $self->{_DATASTORE}->_purge_objects( $keep_db, $make_tally );
        $self->{_DATASTORE}->_update_recycle_ids( $keep_db );
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

            $newstore->{_DATASTORE}{DATA_STORE}->ensure_entry_count( $keep_id - 1 );
            $newstore->_dirty( $obj, $keep_id );
            $newstore->_stow( $obj, $keep_id );
        } elsif( $self->{_DATASTORE}{DATA_STORE}->has_id( $keep_id ) ) {
            push @purges, $keep_id;
        }
    } #each entry id

    # reopen data store
    $self->{_DATASTORE} = Yote::YoteDB->open( $self, $self->{args} );
    move( $original_dir, $backdir ) or die $!;
    move( $newdir, $original_dir ) or die $!;

    \@purges;

} #_copy_active_ids

=head2 has_id

 Returns true if there is a valid reference linked to the id

=cut
sub has_id {
    my( $self, $id ) = @_;
    return $self->{_DATASTORE}{DATA_STORE}->has_id( $id );
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
            $cls = ref(tied %$ref) eq 'Yote::ArrayGatekeeper' ? 'Yote::ArrayGatekeeper' : 'ARRAY';
            $cls = 'ARRAY';
        } elsif( $ref eq 'HASH' ) {
            $cls = ref(tied %$ref) eq 'Yote::BigHash' ? 'Yote::BigHash' : 'HASH';
        } else {
            $cls = $ref;
        }
        my( $text_rep ) = $self->_raw_data( $obj );
        push( @odata, [ $self->_get_id( $obj ), $cls, $text_rep ] );
    }
    $self->{_DATASTORE}->_stow_all( \@odata );
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
        $cls = ref(tied %$ref) eq 'Yote::BigHash' ? 'Yote::BigHash' : 'HASH';
    } else {
        $cls = $ref;
    }
    my $id = $self->_get_id( $obj );
    my( $text_rep ) = $self->_raw_data( $obj );
    $self->{_DATASTORE}->_stow( $id, $cls, $text_rep );
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
    $self->{_DATASTORE} = Yote::YoteDB->open( $self, $args );
    $self;
} #_new

sub _init {
    my $self = shift;
    for my $pkg ( qw( Yote::Obj Yote::Array Yote::Hash Yote::ArrayGatekeeper Yote::BigHash ) ) {
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
    shift->{_DATASTORE}->_first_id();
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
        return $ref->[0];
    }
    elsif( $class eq 'ARRAY' ) {
        my $tied = tied @$ref;
        if( $tied ) {
             $tied->[0] ||= $self->{_DATASTORE}->_get_id( "ARRAY" );
            return $tied->[0];
        }
        my( @data ) = @$ref;
        my $id = $self->{_DATASTORE}->_get_id( $class );
        tie @$ref, 'Yote::ArrayGatekeeper', $self, $id;
        push( @$ref, @data ) if @data;
        $self->_dirty( $ref, $id );
        $self->_store_weak( $id, $ref );
        return $id;
    }
    elsif( $class eq 'Yote::Hash' || $class eq 'Yote::BigHash' ) {
        my $wref = $ref;
        return $ref->[0];
    }
    elsif( $class eq 'HASH' ) {
        my $tied = tied %$ref;
        if( $tied ) {
            my $useclass = ref($tied) eq 'Yote::BigHash' ? 'Yote::BigHash' : 'HASH';
            $tied->[0] ||= $self->{_DATASTORE}->_get_id( $useclass );
            return $tied->[0];
        }
        my $id = $self->{_DATASTORE}->_get_id( $class );

        my( %vals ) = %$ref;

        tie %$ref, 'Yote::BigHash', $self, $id;
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
            $ref->{ID} = $self->{_DATASTORE}->_first_id( $class );
        } else {
            $ref->{ID} ||= $self->{_DATASTORE}->_get_id( $class );
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
        $self->{_DATASTORE}->_stow( $id,'ARRAY', $text_rep );
        $self->_clean( $id );
    }
    elsif( $class eq 'HASH' ) {
        $self->{_DATASTORE}->_stow( $id,'HASH',$text_rep );
        $self->_clean( $id );
    }
    elsif( $class eq 'Yote::Array' ) {
        if( $self->_is_dirty( $id ) ) {
            $self->{_DATASTORE}->_stow( $id,'ARRAY',$text_rep );
            $self->_clean( $id );
        }
        for my $child (@$data) {
            if( $child =~ /^[0-9]/ && $self->{_DIRTY}->{$child} ) {
                $self->_stow( $child, $self->{_DIRTY}->{$child} );
            }
        }
    }
    elsif( $class eq 'Yote::ArrayGatekeeper' ) {
        if( $self->_is_dirty( $id ) ) {
            $self->{_DATASTORE}->_stow( $id,'Yote::ArrayGatekeeper',$text_rep );
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
            $self->{_DATASTORE}->_stow( $id, 'HASH', $text_rep );
        }
        $self->_clean( $id );
        for my $child (values %$data) {
            if( $child =~ /^[0-9]/ && $self->{_DIRTY}->{$child} ) {
                $self->_stow( $child, $self->{_DIRTY}->{$child} );
            }
        }
    }
    elsif( $class eq 'Yote::BigHash' ) {
        if( $self->_is_dirty( $id ) ) {
            $self->{_DATASTORE}->_stow( $id, 'Yote::BigHash', $text_rep );
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
            $self->{_DATASTORE}->_stow( $id, $class, $text_rep );
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
    # TODO : clean this up nice
    my( $r, $is_array, $is_hash, $hash_type, $tied );
    if( $class eq 'ARRAY' ) {
        $tied = tied @$obj;
        if( $tied ) {
            $r = $tied->[1];
            $is_array = ref( $tied );
        } else {
            die;
        }
    }
    elsif( $class eq 'HASH' ) {
        my $tied = tied %$obj;
        if( $tied ) {
            $r = $tied->[1];
            $is_hash = $tied->[6];
            $hash_type = $tied->[8];
        } else {
            die;
        }
    }
    elsif( $class eq 'Yote::Array' ) {
        $r = $obj->[1];
        $is_array = 'Yote::Array';
    }
    elsif( $class eq 'Yote::ArrayGatekeeper' ) {
        $tied = $obj;
        $r = $obj->[1];
        $is_array = 'Yote::ArrayGatekeeper';
    }
    elsif( $class eq 'Yote::Hash' ) {
        # not seeing is_hash for the old hashes as there is no extra data for them
        $r = $obj->[1];
    }
    elsif( $class eq 'Yote::BigHash' ) {
        $r = $obj->[1];
        $is_hash = $obj->[6];
        $hash_type = $obj->[8];
    }
    else {
        $r = $obj->{DATA};
    }

    if( $is_hash ) {
        if( $hash_type eq 'S' ) {
            return join( "`", $hash_type, $is_hash, map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } %$r ), $r;
        }
        return join( "`", $hash_type, $is_hash, map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } @$r ), $r;
    }
    if( $is_array eq 'Yote::ArrayGatekeeper' ) {
        return join( "`", $tied->[6],$tied->[4],$tied->[5],$tied->[7], map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } @$r ), $r;
    } elsif( $is_array ) {
        return join( "`", map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } @$r ), $r;
    }
    return join( "`", map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } %$r ), $r;

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

sub TIEARRAY {
    my( $class, $obj_store, $id, @list ) = @_;
    my $storage = [];

    # once the array is tied, an additional data field will be added
    # so obj will be [ $id, $storage, $obj_store ]
    my $obj = bless [$id,$storage,$obj_store], $class;
    for my $item (@list) {
        push( @$storage, $item );
    }
    return $obj;
}

sub FETCH {
    my( $self, $idx ) = @_;
    return $self->[2]->_xform_out ( $self->[1][$idx] );
}

sub FETCHSIZE {
    my $self = shift;
    return scalar(@{$self->[1]});
}

sub STORE {
    my( $self, $idx, $val ) = @_;
    $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$self->[0]}, $self->[0] );
    $self->[1][$idx] = $self->[2]->_xform_in( $val );
}
sub STORESIZE {
    my( $self, $size ) = @_;
    my $aref = $self->[1];
    $#$aref = $size-1;
}

sub EXISTS {
    my( $self, $idx ) = @_;
    return defined( $self->[1][$idx] );
}
sub DELETE {
    my( $self, $idx ) = @_;
    $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$self->[0]}, $self->[0] );
    delete $self->[1][$idx];
}

sub CLEAR {
    my $self = shift;
    $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$self->[0]}, $self->[0] );
    @{$self->[1]} = ();
}
sub PUSH {
    my( $self, @vals ) = @_;
    $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$self->[0]}, $self->[0] );
    push( @{$self->[1]}, map { $self->[2]->_xform_in($_) } @vals );
}
sub POP {
    my $self = shift;
    $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$self->[0]}, $self->[0] );
    return $self->[2]->_xform_out( pop @{$self->[1]} );
}
sub SHIFT {
    my( $self ) = @_;
    $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$self->[0]}, $self->[0] );
    my $val = splice @{$self->[1]}, 0, 1;
    return $self->[2]->_xform_out( $val );
}
sub UNSHIFT {
    my( $self, @vals ) = @_;
    $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$self->[0]}, $self->[0] );
    unshift @{$self->[1]}, map {$self->[2]->_xform_in($_)} @vals;
}
sub SPLICE {
    my( $self, $offset, $length, @vals ) = @_;
    $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$self->[0]}, $self->[0] );
    return map { $self->[2]->_xform_out($_) } splice @{$self->[1]}, $offset, $length, map {$self->[2]->_xform_in($_)} @vals;
}
sub EXTEND {}

sub DESTROY {
    my $self = shift;
    delete $self->[2]->{_WEAK_REFS}{$self->[0]};
}

# ---------------------------------------------------------------------------------------------------------------------

package Yote::ArrayGatekeeper;

############################################################################################################
# This module is used transparently by Yote to link arrays into its graph structure. This is not meant to  #
# be called explicitly or modified.                                                                        #
############################################################################################################

use strict;
use warnings;

no warnings 'uninitialized';
use Tie::Array;

$Yote::ArrayGatekeeper::BLOCK_SIZE  = 1024;
$Yote::ArrayGatekeeper::BLOCK_COUNT = 1024;

use constant {
    ID          => 0,
    BLOCKS      => 1,
    DSTORE      => 2,
    CAPACITY    => 3,
    BLOCK_COUNT => 4,
    BLOCK_SIZE  => 5,
    ITEM_COUNT  => 6,
    LEVEL       => 7,
};

sub TIEARRAY {
    my( $class, $obj_store, $id, $item_count, $block_count, $block_size, $level, @list ) = @_;

    $block_size  ||= $Yote::ArrayGatekeeper::BLOCK_SIZE;
    $block_count ||= $Yote::ArrayGatekeeper::BLOCK_COUNT;
    $item_count  ||= 0;
    $level       ||= 1;
    my $capacity = $block_size * $block_count;

    my $blocks = [@list];

    # once the array is tied, an additional data field will be added
    # so obj will be [ $id, $storage, $obj_store ]
    my $obj = bless [$id,$blocks,$obj_store,$capacity,$block_count,$block_size, $item_count, $level], $class;
    return $obj;
} #TIEARRAY

sub _ensure_capacity {
    my( $self, $size ) = @_;

    if( $size > $self->[CAPACITY] ) {
        my $store = $self->[DSTORE];
        #
        # make a new gatekeeper and moves the buckets of this
        # one into the new gatekeeper
        #
        my $new_id = $store->{_DATASTORE}->_get_id( 'Yote::ArrayGatekeeper' );
        my $newkeeper = [];
        tie @$newkeeper, 'Yote::ArrayGatekeeper', $store, $new_id, $self->[ITEM_COUNT], $self->[BLOCK_COUNT], $self->[BLOCK_SIZE], $self->[LEVEL], @{$self->[BLOCKS]};

        $store->_store_weak( $new_id, $newkeeper );
        $store->_dirty( $store->{_WEAK_REFS}{$new_id}, $new_id );

        $self->[LEVEL]++;
        $self->[BLOCKS] = [ $new_id ];
        $self->[BLOCK_SIZE] = $self->[CAPACITY];
        $self->[CAPACITY] = $self->[BLOCK_SIZE] * $self->[BLOCK_COUNT];
        $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );
    }

} #_ensure_capacity

sub _dirty {
    my $self = shift;
    $self->[DSTORE]->_dirty( $self->[DSTORE]{_WEAK_REFS}{$self->[ID]}, $self->[ID] );
}

# returns the block object ( behind the tied ), the block index
# and the first item index in the block
sub _block {
    my( $self, $idx ) = @_;
    $self->_ensure_capacity( $idx + 1 );


    my $block_idx = int($idx / $self->[BLOCK_SIZE]); #block size

    my $store = $self->[DSTORE];

    my $block_id = $self->[BLOCKS][$block_idx];
    my $block;
    if( $block_id ) {
        $block = $store->fetch($block_id);
    } elsif( $self->[LEVEL] == 1 ) {
        $block = [];
        my $block_id = $store->{_DATASTORE}->_get_id( "ARRAY" );
        tie @$block, 'Yote::Array', $store, $block_id;
        $store->_store_weak( $block_id, $block );
        $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$block_id}, $block_id );

        $self->[BLOCKS][$block_idx] = $block_id;
        $self->_dirty;
    } else {
        my $firstblock = tied( @{$store->fetch($self->[BLOCKS][0])} );

        $block = [];
        my $block_id = $store->{_DATASTORE}->_get_id( "Yote::ArrayGatekeeper" );
        tie @$block, 'Yote::ArrayGatekeeper', $store, $block_id, 0, $firstblock->[BLOCK_COUNT], $firstblock->[BLOCK_SIZE], $firstblock->[LEVEL];
        $store->_store_weak( $block_id, $block );
        $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$block_id}, $block_id );

        $self->[BLOCKS][$block_idx] = $block_id;
        $self->_dirty;
    }
    return ( $block, tied( @$block), $block_idx, $block_idx * $self->[BLOCK_SIZE] );
}

sub FETCH {
    my( $self, $idx ) = @_;
    my( $block, $tied_block, $block_idx, $block_start_idx ) = $self->_block( $idx );
    return $tied_block->FETCH( $idx - $block_start_idx );
}

sub FETCHSIZE {
    shift->[ITEM_COUNT];
}

sub STORE {
    my( $self, $idx, $val ) = @_;
    my( $block, $tied_block, $block_idx, $block_start_idx ) = $self->_block( $idx );
    my $last_block_idx = $self->[ITEM_COUNT] - 1;
    $tied_block->STORE( $idx - $block_start_idx, $val );
    if( $idx > $last_block_idx ) {
        $self->[ITEM_COUNT] = $idx + 1;
    }
}
sub STORESIZE {
    my( $self, $size ) = @_;
    # fixes the size of the array
    if( $size < $self->[ITEM_COUNT] ) {
        my( $block, $tied_block, $block_idx, $block_start_idx ) = $self->_block( $self->[BLOCK_SIZE] * int($size/$self->[BLOCK_SIZE]) );
        my $blocks = $self->[BLOCKS];
        $#$blocks = $block_idx; #removes further blocks
        $tied_block->STORESIZE( $size - $block_start_idx );
        $self->_dirty;
        $self->[ITEM_COUNT] = $size;
    }
}

sub EXISTS {
    my( $self, $idx ) = @_;
    my( $block, $tied_block, $block_idx, $block_start_idx ) = $self->_block( $idx );
    return $tied_block->EXISTS( $idx - $block_start_idx );
}
sub DELETE {
    my( $self, $idx ) = @_;
    my( $block, $tied_block, $block_idx, $block_start_idx ) = $self->_block( $idx );

    if( (1+$idx) == $self->[ITEM_COUNT] ) {
        # in this case, it is removing the last item here. so shorten the
        # array until the
        my $curr_block_start_idx = $block_start_idx;
        my $blocks = $self->[BLOCKS];
        my $prev_idx = $idx - 1;
        while( ! $self->EXISTS( $prev_idx ) && $prev_idx >= 0 ) {
            if( $curr_block_start_idx == $prev_idx ) {
                pop @$blocks;
            }
            $self->[ITEM_COUNT]--;
            $prev_idx--;
        }
        $self->_dirty;
    }
    return $tied_block->DELETE( $idx - $block_start_idx );
}

sub CLEAR {
    my $self = shift;
    $self->_dirty;
    @{$self->[1]} = ();
}
sub PUSH {
    my( $self, @vals ) = @_;

    return unless @vals;

    $self->_ensure_capacity( $self->[ITEM_COUNT] + @vals );

    my( $block, $tied_block, $block_idx, $block_start_idx ) = $self->_block( $self->[ITEM_COUNT] );

    $self->[ITEM_COUNT] += @vals;
    $self->_dirty;
    my $idx_at = 0;
    while( @vals ) {

        $idx_at += $self->[BLOCK_SIZE];
        my $room = $self->[BLOCK_SIZE] - ($tied_block->FETCHSIZE);
        my( @part ) = splice @vals, 0, $room;
        $tied_block->PUSH( @part );
        if( @vals ) {
            ($block,$tied_block,undef,undef) = $self->_block( $idx_at );
        }
    }
}
sub POP {
    my $self = shift;

    my $blocks = $self->[BLOCKS];
    if( @$blocks ) {
        my $lastblock = tied @{$self->[DSTORE]->fetch($blocks->[$#$blocks])};
        my $val = $lastblock->POP;
        if( @$lastblock == 0 ) {
            pop @$blocks;
        }
        $self->[ITEM_COUNT]--;
        $self->_dirty;
        return $val;
    }
    return;
}
sub SHIFT {
    my( $self ) = @_;
    my $blocks = $self->[1];
    my $store = $self->[DSTORE];
    if( @$blocks ) {
        my $block = tied( @{$store->fetch( $blocks->[0] )} );
        my $val = $block->SHIFT;
        for( my $i=1; $i<@$blocks; $i++ ) {
            my $now_block = tied( @{$store->fetch( $blocks->[$i] )} );
            my $prev_block = tied( @{$store->fetch( $blocks->[$i-1] )} );
            $prev_block->PUSH( $now_block->SHIFT );
            if( $#$blocks == -1 ) {
                pop @$blocks;
                last;
            }
        }
        $self->[ITEM_COUNT]--;
        $self->_dirty;
        return $val;
    }
    return;
}

sub UNSHIFT {
    shift->_unshift(0,@_);
}

sub _unshift {
    my( $self, $offset, @vals ) = @_;

    print STDERR " _unshift ($self) $offset (".join(",",@vals).")\n";
    
    return unless @vals;

    my $newcount = $self->[ITEM_COUNT] + @vals;
    $self->_ensure_capacity( $newcount );

    my( $block, $tied_block, $block_idx, $block_start_idx ) = $self->_block( $offset );

    if( $self->[LEVEL] == 1 ) {
        while( @vals ) {
            print STDERR "UNSHIFT ($self) ($offset vs $block_start_idx)\n";
            print STDERR " About to splice ($tied_block) to $offset adding (".join(',',@vals).") to ".join(',',@$block).")\n";
            $tied_block->SPLICE( $offset , 0, @vals );
            print STDERR "   block ($tied_block) spliced to (".join(",",@$block)."\n";
            $offset = 0;
            print STDERR "   block ($tied_block) last idx is $#$block and size is $self->[BLOCK_SIZE]\n";
            if( $#$block >= $self->[BLOCK_SIZE] ) {
                (@vals) = @$block[$self->[BLOCK_SIZE]..$#$block];
                $#$block = $self->[BLOCK_SIZE] - 1;
                print STDERR "   vals blocked to [$block_idx] (".join(",",@vals)." ) and block ($tied_block) $#$block (size $self->[BLOCK_SIZE]) at (".join(',',@$block).")\n";
                ( $block, $tied_block, $block_idx, $block_start_idx ) = $self->_block( (1+$block_idx)*$self->[BLOCK_SIZE] );
                print STDERR "   now on block ($tied_block) $block_idx : (".join(',',@$block).")\n";
            } else {
                print STDERR "   block ($tied_block) done, no more vals\n";
                print STDERR "     block ($tied_block) : " .join(',',@$block)."\n";
                @vals = ();
            }
        }
    } else {
        while( @vals ) {
            my $overflow = (@vals + $tied_block->[ITEM_COUNT]) - $self->[BLOCK_SIZE];
            if( $overflow > 0 ) {
                my $cut_index = $self->[BLOCK_SIZE] - @vals;
                my( @backlog ) = @$block[$cut_index..$#$block];

                $tied_block->STORESIZE( $cut_index );

                my @additions = splice @vals, 0, (1+$cut_index);
                print STDERR "   vals splice to additions (".join(",",@vals)."\n";
                $tied_block->_unshift( $offset, @additions ); #offset is only on the first block
                $offset = 0;
                push @vals, @backlog;
                print STDERR "   vals added backlog (".join(",",@vals)."\n";
                if( @vals ) {
                    ( $block, $tied_block, $block_idx, $block_start_idx ) = $self->_block( (1+$block_idx)*$self->[BLOCK_SIZE] );
                }
            } else {
                print STDERR " About to splice ($tied_block) to $offset adding (".join(',',@vals).") to ".join(',',@$block).")\n";
                $tied_block->SPLICE( $offset, 0, @vals );
                print STDERR "   block ($tied_block) now ".join(',',@$block)."\n";
                @vals = ();
            }
        }
    }

    $self->[ITEM_COUNT] = $newcount;
    $self->_dirty;

} #UNSHIFT

sub SPLICE {
    my( $self, $offset, $remove_length, @vals ) = @_;

    return unless @vals || $remove_length;

    my @removed;

    my $delta = @vals - $remove_length;
    my $new_size = $self->[ITEM_COUNT] + $delta;


    print STDERR "SPLICE delta ($self) : $delta, new size : $new_size\n";
    
    if( $delta > 0 ) {
        $self->_ensure_capacity( $new_size );
    }

    my $blocks = $self->[BLOCKS];
    my( $xx ) = $self->_block( $offset - 1  );
    my( $yy ) = $self->_block( $#$blocks * $self->[BLOCK_SIZE]  );
    print STDERR Data::Dumper->Dump([$xx,$yy,"CHEW ($self)"]);


    #
    # add things
    #

    if( @vals ) {
        # this adjusts the item count
        $self->_unshift( $offset, @vals );
        my( $xx ) = $self->_block( $offset - 1  );
        my( $yy ) = $self->_block( $offset  );
        print STDERR Data::Dumper->Dump([$xx,$yy,"OOGB ($self $xx/$yy) ($offset) ($self->[ITEM_COUNT])"]);
    }

    if( $remove_length > 0 ) {
    #
    # remove things
    #
        my $remove_start_idx = $offset + @vals;
        my $remove_end_idx   = $remove_start_idx + $remove_length;
        my $new_last_idx     = $new_size - 1;

        print STDERR " ($self) rem start idx $remove_start_idx, end idx $remove_end_idx, new last idx $new_last_idx\n";
        while ( $remove_start_idx <= $new_last_idx ) {
        
            my( $remstart ) = $self->_block( $remove_start_idx );
            my( $remend ) = $self->_block( $remove_end_idx + 1 );
            print STDERR Data::Dumper->Dump([$remstart,$remend,"WSDF"]);
        
        
            my $removed = $self->FETCH( $remove_start_idx );
            print STDERR "  Removign ($self) '$removed' at idx $remove_start_idx\n";
            print STDERR "  Gonna replace with '".$self->FETCH($remove_end_idx)."'\n";
            if( @removed < $remove_length ) {
                push @removed, $removed;
            }
            print STDERR "  Moving '".$self->FETCH($remove_end_idx)." at idx $remove_end_idx to $remove_start_idx\n";
            $self->STORE( $remove_start_idx, $self->FETCH( $remove_end_idx ) );
            print STDERR "  Nowish ".$self->FETCH($remove_start_idx)." and ".$self->FETCH($remove_end_idx)."\n";
            $remove_start_idx++;
            $remove_end_idx++;
            print STDERR "  Thenish ".$self->FETCH($remove_start_idx)." and ".$self->FETCH($remove_end_idx)."\n";
        }
    }
    #
    # Trim this array to its new size
    #
    $self->STORESIZE( $new_size );

    print STDERR "Returning ($self) removed (".join(',',@removed).")\n";
    
    return @removed;

} #SPLICE

sub EXTEND {
}

sub DESTROY {
    my $self = shift;
    delete $self->[2]->{_WEAK_REFS}{$self->[0]};
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

use Tie::Hash;

sub TIEHASH {
    my( $class, $obj_store, $id, %hash ) = @_;
    my $storage = {};
    # after $obj_store is a list reference of
    #                 id, data, store
    my $obj = bless [ $id, $storage,$obj_store ], $class;
    for my $key (keys %hash) {
        $storage->{$key} = $hash{$key};
    }
    return $obj;
}

sub STORE {
    my( $self, $key, $val ) = @_;
    $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$self->[0]}, $self->[0] );
    $self->[1]{$key} = $self->[2]->_xform_in( $val );
}

sub FIRSTKEY {
    my $self = shift;
    my $a = scalar keys %{$self->[1]};
    my( $k, $val ) = each %{$self->[1]};
    return wantarray ? ( $k => $val ) : $k;
}
sub NEXTKEY  {
    my $self = shift;
    my( $k, $val ) = each %{$self->[1]};
    return wantarray ? ( $k => $val ) : $k;
}

sub FETCH {
    my( $self, $key ) = @_;
    return $self->[2]->_xform_out( $self->[1]{$key} );
}

sub EXISTS {
    my( $self, $key ) = @_;
    return defined( $self->[1]{$key} );
}
sub DELETE {
    my( $self, $key ) = @_;
    $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$self->[0]}, $self->[0] );
    return delete $self->[1]{$key};
}
sub CLEAR {
    my $self = shift;
    $self->[2]->_dirty( $self->[2]{_WEAK_REFS}{$self->[0]}, $self->[0] );
    %{$self->[1]} = ();
}

sub DESTROY {
    my $self = shift;
    delete $self->[2]->{_WEAK_REFS}{$self->[0]};
}


# ---------------------------------------------------------------------------------------

package Yote::BigHash;

######################################################################################
# This module is used transparently by Yote to link hashes into its graph structure. #
# This is not meant to  be called explicitly or modified.                            #
######################################################################################

use strict;
use warnings;

no warnings 'uninitialized';
no warnings 'numeric';

use Tie::Hash;

$Yote::BigHash::SIZE = 977;

use constant {
    ID     => 0,
    DATA   => 1,
    DSTORE => 2,
    NEXT   => 3,
    KEYS   => 4,
    DEEP   => 5,
    SIZE   => 6,
    THRESH => 7,
    TYPE   => 8,
};

sub _bucket {
    my( $self, $key, $return_undef ) = @_;
    my $hval = 0;
    foreach (split //, $key) {
        $hval = $hval*33 - ord($_);
    }

    $hval = $hval % $self->[SIZE];
    my $obj_id = $self->[DATA][$hval];
    my $store = $self->[DSTORE];
    unless( $obj_id ) {
        return ($hval, undef) if $return_undef;
        my $bucket = [];
        my $id = $store->_get_id( $bucket );
        $self->[DATA][$hval] = $id;
        return $hval, $bucket;
    }
    $hval, $store->_xform_out( $obj_id );
}

sub TIEHASH {
    my( $class, $obj_store, $id, $type, $size, @fetch_buckets ) = @_;

    $type ||= 'S'; #small
    $size ||= $Yote::BigHash::SIZE;

    my $deep_buckets = $type eq 'B' ?
        [ map { $_ > 0 && ref( $obj_store->_xform_out($_) ) eq 'HASH' ? 1 : 0 } @fetch_buckets ] : [];

    no warnings 'numeric';
    #
    # after $obj_store is a list reference of
    #                 id, data, store
    my $obj;
    if( $type eq 'S' ) {
        $obj = bless [ $id, {@fetch_buckets}, $obj_store, [], 0, $deep_buckets, $size, $size * 2, $type ], $class;
    }
    else {
        $obj = bless [ $id, [@fetch_buckets], $obj_store, [], 0, $deep_buckets, $size, $size * 2, $type ], $class;
    }

    return $obj;
}

sub STORE {
    my( $self, $key, $val ) = @_;
    my $store = $self->[DSTORE];
    $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );

    if( $self->[TYPE] eq 'S' ) {
        my $data = $self->[DATA];
        $self->[KEYS]++ unless exists $data->{$key}; #obj count
        $data->{$key} = $store->_xform_in($val);

        if( $self->[KEYS] > $self->[THRESH] ) {
            $self->[TYPE] = 'B'; #big
            #convert to buckets
            $self->[DATA] = [];
            for my $key (keys %$data) {
                $self->STORE( $key, $store->_xform_out($data->{$key}) );
            }
        }

        return;
    }

    my( $bid, $bucket ) = $self->_bucket( $key );

    if( $self->[DEEP][$bid] ) {
        $self->[KEYS]++ unless exists $bucket->{$key}; #obj count
        $bucket->{$key} = $val;
    } else {
        if( @$bucket > $self->[THRESH] ) {
            my $newbuck = {};
            my $id = $store->_get_id( $newbuck );

            my $tied = tied %$newbuck;
            $tied->[SIZE]   = $self->[SIZE] * 2;
            $tied->[THRESH] = $tied->[SIZE] * 2;
            for( my $i=0; $i<$#$bucket; $i+=2 ) {
                $newbuck->{$bucket->[$i]} = $bucket->[$i+1];
            }
            $self->[KEYS]++ unless exists $newbuck->{$key};
            $newbuck->{$key} = $val;
            $self->[DEEP][$bid] = 1;
            $self->[DATA][$bid] = $id;
            return;
        }
        for( my $i=0; $i<$#$bucket; $i+=2 ) {
            if( $bucket->[$i] eq $key ) {
                $bucket->[$i+1] = $val;

                return;
            }
        }
        $self->[KEYS]++; #obj count
        push @$bucket, $key, $val;
    }
} #STORE

sub FIRSTKEY {
    my $self = shift;

    if( $self->[TYPE] eq 'S' ) {
        my $a = scalar keys %{$self->[DATA]}; #reset things
        my( $k, $val ) = each %{$self->[DATA]};
        return wantarray ? ( $k => $val ) : $k;
    }
    @{ $self->[NEXT] } = ( 0, undef, undef );
    return $self->NEXTKEY;
}

sub NEXTKEY  {
    my $self = shift;

    if( $self->[TYPE] eq 'S' ) {
        my( $k, $val ) = each %{$self->[DATA]};
        return wantarray ? ( $k, $val ) : $k;
    }

    my $buckets = $self->[DATA];
    my $store   = $self->[DSTORE];
    my $current = $self->[NEXT];

    my( $bucket_idx, $idx_in_bucket ) = @$current;

    for( my $bid = $bucket_idx; $bid < @$buckets; $bid++ ) {
        my $bucket = defined( $bid ) ? $store->_xform_out($buckets->[$bid]) : undef;
        if( $bucket ) {
            if( $self->[DEEP][$bid] ) {
                my $tied = tied %$bucket;
                my $key = defined( $idx_in_bucket) ? $tied->NEXTKEY : $tied->FIRSTKEY;
                if( defined($key) ) {
                    # the bucket must be there to keep a weak reference
                    # to itself. If it was not here, it would load from
                    # the filesystem each call to NEXTKEY
                    @$current = ( $bid, 0, $bucket );
                    return wantarray ? ( $key => $bucket->{$key} ): $key;
                }
            } else {
                if( $idx_in_bucket < $#$bucket ) {
                    @$current = ( $bid, $idx_in_bucket + 2, undef );
                    my $key = $bucket->[$idx_in_bucket||0];
                    return wantarray ? ( $key => $bucket->[$idx_in_bucket+1] ) : $key;
                }
            }
            undef $bucket;
        }
        undef $idx_in_bucket;
    }
    @$current = ( 0, undef, undef );
    return undef;

} #NEXTKEY

sub FETCH {
    my( $self, $key ) = @_;
    if( $self->[TYPE] eq 'S' ) {
        return $self->[DSTORE]->_xform_out( $self->[DATA]{$key} );
    }
    my( $bid, $bucket ) = $self->_bucket( $key );
    if( $self->[DEEP][$bid] ) {
        return $bucket->{$key};
    } else {
        for( my $i=0; $i<$#$bucket; $i+=2 ) {
            if( $bucket->[$i] eq $key ) {
                return $bucket->[$i+1];
            }
        }
    }
} #FETCH

sub EXISTS {
    my( $self, $key ) = @_;
    if( $self->[TYPE] eq 'S' ) {
        return exists $self->[DATA]{$key};
    }

    my( $bid, $bucket ) = $self->_bucket( $key );
    if( $self->[DEEP][$bid] ) {
        return exists $bucket->{$key};
    } else {
        for( my $i=0; $i<$#$bucket; $i+=2 ) {
            if( $bucket->[$i] eq $key ) {
                return 1;
            }
        }
    }
    return 0;
} #EXISTS

sub DELETE {
    my( $self, $key ) = @_;

    my $store = $self->[DSTORE];

    if( $self->[TYPE] eq 'S' ) {
        if( exists $self->[DATA]{$key} ) {
            $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );
            $self->[KEYS]--;
            delete $self->[DATA]{$key};
        }
        return;
    }

    my( $bid, $bucket ) = $self->_bucket( $key, 'return_undef' );
    return 0 unless $bucket;

    # TODO - see if the buckets revert back to arrays
    if( $self->[DEEP][$bid] ) {
        $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );
        $self->[KEYS]-- if exists $bucket->{$key}; #obj count
        return delete $bucket->{$key};
    } else {
        for( my $i=0; $i<$#$bucket; $i+=2 ) {
            if( $bucket->[$i] eq $key ) {
                splice @$bucket, $i, 2;
                $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );
                $self->[KEYS]--; #obj count
                return 1;
            }
        }
    }
    return 0;
} #DELETE

sub CLEAR {
    my $self = shift;
    my $store = $self->[DSTORE];
    $self->[KEYS] = 0;
    $store->_dirty( $store->{_WEAK_REFS}{$self->[ID]}, $self->[ID] );

    if( $self->[TYPE] eq 'S' ) {
        $self->[DATA] = {};
    }

    my $buckets = $self->[DATA];
    for( my $bid=0; $bid<@$buckets; $bid++ ) {
        if( $self->[DEEP][$bid] ) {
            my $buck = tied %{$buckets->[$bid]};
            $buck->CLEAR;
        } else {
            my $buck = $buckets->[$bid];
            splice @$buck, 0, scalar( @$buck );
        }
    }
    splice @$buckets, 0, scalar(@$buckets);
}

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

  if( $class eq 'ARRAY' || $class eq 'HASH' ) {
      $ret->[DATA] = $parts;
  } else {
      $ret->[DATA] = { @$parts };
  }

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
        if( $obj_arry->[CLS] eq 'HASH' ) {
            my $type = shift @{$obj_arry->[DATA]};
            shift @{$obj_arry->[DATA]}; #remove the size
            if( $type eq 'S' ) {
                my $d = {@{$obj_arry->[DATA]}};
                ( @additions ) = grep { /^[^v]/ && ! $seen{$_}++ } values %$d;
            } else { #BIG type
                ( @additions ) = grep { /^[^v]/ && ! $seen{$_}++ } @{$obj_arry->[DATA]};
            }
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

=head1 AUTHOR
       Eric Wolf        coyocanid@gmail.com

=head1 COPYRIGHT AND LICENSE

       Copyright (c) 2016 Eric Wolf. All rights reserved.  This program is free software; you can redistribute it and/or modify it
       under the same terms as Perl itself.

=head1 VERSION
       Version 2.01  (July, 2017))

=cut
