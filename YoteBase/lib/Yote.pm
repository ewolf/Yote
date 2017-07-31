package Yote;

use strict;
use warnings;
use warnings FATAL => 'all';
no  warnings 'uninitialized';

use vars qw($VERSION);

$VERSION = '3.0';

sub open_store {
    my $path = pop;
    my $store = Yote::ObjStore->open_store( $path );
    $store;
}

# --------------------------------------------------------------------------------

package Yote::ObjStore;

use strict;
use warnings;
no warnings 'numeric';
no warnings 'uninitialized';
no warnings 'recursion';

use Data::RecordStore;
use File::Copy;
use File::Path qw(make_path remove_tree);
use Scalar::Util qw(weaken);

use constant {
    RECORD_STORE => 0,
    DIRTY        => 1,
    WEAK         => 2,

    ID           => 0,
};

sub fetch_root {
    my $self = shift;
    my $root = $self->_fetch( 1 );
    unless( $root ) {
        my $first_id = $self->_new_id;
        die "Fetch Root must have ID of 1, got '$first_id'" unless $first_id == 1;
        $root = bless [ 1, {}, $self ], 'Yote::Obj';
    }
    $root;
} #fetch_root

sub open_store {
    my( $cls, $path ) = @_;

    #
    # Yote subpackages are not normally in %INC and should always be loaded.
    #
    for my $pkg ( qw( Yote::Obj Yote::Array Yote::Hash ) ) {
        $INC{ $pkg } or eval("use $pkg");
    }

    bless [
        Data::RecordStore->open( $path ),
        {}, #DIRTY CACHE
        {}  #WEAK CACHE
        ], $cls;
} #open_store

sub newobj {
    # works with newobj( { my data } ) or newobj( 'myclass', { my data } )
    my $self = shift;
    my $data = pop;
    my $class = pop || 'Yote::Obj';

    my $id = $self->_new_id;
    my $obj = bless [ $id,
                      { map { $_ => $self->_xform_in( $data->{$_} ) } keys %$data},
                      $self ], $class;
    $self->_dirty( $obj, $id );
    $self->_store_weak( $id, $obj );
    $obj->_init(); #called the first time the object is created.
    $obj;
} #newobj

sub stow_all {
    my $self = shift;
    for my $id ( keys %{$self->[DIRTY]} ) {
        my $obj = $self->[DIRTY]{$id};
        next unless $obj;
        my $cls = ref( $obj );

        my $thingy = $cls eq 'HASH' ? tied( %$obj ) : $cls eq 'ARRAY' ?  tied( @$obj ) : $obj;
        my $text_rep = $thingy->_freezedry;
        my $class = ref( $thingy );

        $self->[RECORD_STORE]->stow( "$class $text_rep", $id );
    }
    $self->[DIRTY] = {};

} #stow_all

sub _fetch {
    my( $self, $id ) = @_;
    return undef unless $id;

    my $ref = $self->[DIRTY]{$id} //$self->[WEAK]{$id};
    return $ref if $ref;

    my $stowed = $self->[RECORD_STORE]->fetch( $id );

    return undef unless $stowed;

    my $pos = index( $stowed, ' ' );
    die "Malformed record '$stowed'" if $pos == -1;

    my $class    = substr $stowed, 0, $pos;
    my $dryfroze = substr $stowed, $pos + 1;

    unless( $INC{ $class } ) {
        eval("use $class");
    }

    # so foo` or foo\\` but not foo\\\`
    # also this will never start with a `
    my $pieces = [ split /\`/, $dryfroze, -1 ];

    # check to see if any of the parts were split on escapes
    # like  mypart`foo`oo (should be translated to mypart\`foo\`oo
    if ( 0 < grep { /\\$/ } @$pieces ) {
        my $newparts = [];

        my $is_hanging = 0;
        my $working_part = '';

        for my $part (@$pieces) {

            # if the part ends in a hanging escape
            if ( $part =~ /(^|[^\\])((\\\\)+)?[\\]$/ ) {
                if ( $is_hanging ) {
                    $working_part .= "`$part";
                } else {
                    $working_part = $part;
                }
                $is_hanging = 1;
            } elsif ( $is_hanging ) {
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
        if ( $is_hanging ) {
            die "Error in parsing parts\n";
        }
        $pieces = $newparts;
    } #if there were escaped ` characters

    $class->_reconstitute( $self, $id, $pieces );
} #_fetch

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
    return $self->_fetch( $val );
}

sub _store_weak {
    my( $self, $id, $ref ) = @_;
    die "Store weak called without ref" unless $ref;
    $self->[WEAK]{$id} = $ref;

    weaken( $self->[WEAK]{$id} );
} #_store_weak

sub _dirty {
    # ( $self, $ref, $id )
    $_[0]->[DIRTY]->{$_[2]} = $_[1];
} #_dirty


sub _new_id {
    my( $self ) = @_;
    $self->[RECORD_STORE]->next_id;
} #_new_id

sub _get_id {
    my( $self, $ref ) = @_;

    my $class = ref( $ref );

    die "_get_id requires reference. got '$ref'" unless $class;

    if( $class eq 'ARRAY' ) {
        my $thingy = tied @$ref;
        if( ! $thingy ) {
            my $id = $self->_new_id;
            tie @$ref, 'Yote::Array', $self, $id, 0, $Yote::Array::MAX_BLOCKS, map { $self->_xform_in($_) } @$ref;
            $self->_dirty( $ref, $id );
            $self->_store_weak( $id, $ref );
            return $id;
        }
        $ref = $thingy;
        $class = ref( $ref );
    }
    elsif( $class eq 'HASH' ) {
        my $thingy = tied %$ref;
        if( ! $thingy ) {
            my $id = $self->_new_id;
            my( @keys ) = keys %$ref;
            tie %$ref, 'Yote::Hash', $self, $id, undef, undef, scalar(@keys), map { $_ => $self->_xform_in($ref->{$_}) } @keys;
            $self->_dirty( $ref, $id );
            $self->_store_weak( $id, $ref );
            return $id;
        }
        $ref = $thingy;
        $class = ref( $ref );
    }
    die "Cannot injest object that is not a hash, array or yote obj" unless ( $class eq 'Yote::Hash' || $class eq 'Yote::Array' || $ref->isa( 'Yote::Obj' ) );
    $ref->[ID] ||= $self->_new_id;
    return $ref->[ID];

} #_get_id

# --------------------------------------------------------------------------------

package Yote::Array;


##################################################################################
# This module is used transparently by Yote to link arrays into its graph        #
# structure. This is not meant to be called explicitly or modified.              #
##################################################################################

use strict;
use warnings;

no warnings 'uninitialized';
#no  warnings 'recursion';

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
    UNDERNEATH  => 7,

    WEAK         => 2,
};

sub _freezedry {
    my $self = shift;
    join( "`",
          $self->[LEVEL],
          $self->[BLOCK_COUNT],
          map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } @{$self->[DATA]}
      );
}

sub _reconstitute {
    my( $cls, $store, $id, $data ) = @_;
    my $arry = [];
    tie @$arry, $cls, $store, $id, @$data;
    return $arry;
}

sub TIEARRAY {
    my( $class, $obj_store, $id, $level, $block_count, @list ) = @_;

    my $item_count  = @list;
    my $block_size  = $block_count ** $level;

    die "DSFSOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO" if $block_size == 1&&$level > 0;

    my $use_push = @list > $block_count;

    my $blocks = $use_push ? [] : [@list];

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

    if( $use_push ) {
        $obj->[ITEM_COUNT] = 0;
        $obj->PUSH( map { $obj_store->_xform_out($_) } @list );
    }

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
    my $store = $self->[DSTORE];
    while( $size > $self->[BLOCK_SIZE] * $self->[BLOCK_COUNT] ) {
        die "UNDERNATH" if $self->[UNDERNEATH];
        #
        # need to tie a new block, not use _getblock
        # becaues we do squirrely things with its tied guts
        #
        my $newblock = [];
        my $newid = $store->_new_id;
        tie @$newblock, 'Yote::Array', $store, $newid, $self->[LEVEL], $self->[BLOCK_COUNT];
        $store->_store_weak( $newid, $newblock );
        $store->_dirty( $store->[WEAK]{$newid}, $newid );

        my $tied = tied @$newblock;
        $tied->[DATA] = $self->[DATA];
        $tied->[ITEM_COUNT] = $self->[ITEM_COUNT];
        $tied->[UNDERNEATH] = 1;
        $self->[DATA] = [ $newid ];

        $self->[BLOCK_SIZE] *= $self->[BLOCK_COUNT];
        $self->[LEVEL]++;
        $store->_dirty( $store->[WEAK]{$self->[ID]}, $self->[ID] );
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
        return $store->_fetch( $block_id );
    }

    if( $do_create ) {
        $block_id = $store->_new_id;
        my $block = [];
        my $level = $self->[LEVEL] - 1;
        tie @$block, 'Yote::Array', $store, $block_id, $level, $self->[BLOCK_COUNT];
        
        tied( @$block )->[UNDERNEATH] = 1;

        $store->_store_weak( $block_id, $block );
        $store->_dirty( $store->[WEAK]{$block_id}, $block_id );
        $self->[DATA][$block_idx] = $block_id;
        return $block;
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
        $store->_dirty( $store->[WEAK]{$self->[ID]}, $self->[ID] );
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

    $self->_setcount($size);
#    $self->[ITEM_COUNT] = $size;

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
        $self->[DSTORE]->_dirty( $self->[DSTORE]->[WEAK]{$self->[ID]}, $self->[ID] );
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
    $self->[DSTORE]->_dirty( $self->[DSTORE]->[WEAK]{$self->[ID]}, $self->[ID] );
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
    my( $ret ) =  $self->SPLICE( 0, 1 );
    $ret;
}

sub UNSHIFT {
    my( $self, @vals ) = @_;
    return unless @vals;
    return $self->SPLICE( 0, 0, @vals );
}

sub db {
    return;
    my( $self, $title, $block, $vals, $offset, $remove_length, $removed ) = @_;
    my $LVL = ' * ' x $self->[LEVEL];
    my $buff = "$LVL $title\n\t$LVL BLOCK_SIZE : $self->[BLOCK_SIZE], ID : $self->[ID], LEVEL : $self->[LEVEL], ITEMS : $self->[ITEM_COUNT], BLOCK_COUNT : $self->[BLOCK_COUNT], CAPA : ".($self->[BLOCK_SIZE]*$self->[BLOCK_COUNT]).")\n\t";
    $buff .= "$LVL FULL ($self->[ITEM_COUNT])   [".join(" ",map { $self->FETCH($_) || '.' } 0..($self->[ITEM_COUNT]-1))."]\n\t";
    $buff .= "$LVL CURBLK (".scalar(@$block).")) [".join(' ',map { $_ || '.' } @$block)."]\n\t";
    $buff .= "$LVL REMOVED (".scalar(@$removed).") [".join(",",map { $_ || '.' } @$removed)."]\n" if $removed;
    $buff .= "$LVL SPLICE $offset,$remove_length, VALS (".scalar(@$vals).") [".join(",",map { $_ || '.' } @$vals)."]\n";
    

    print STDERR $buff;# if $Yote::DEBUG && $self->[ID] == 2;

}

sub _setcount {
    my( $self, $count ) = @_;
    die "BADSET $count > $self->[BLOCK_COUNT] * $self->[BLOCK_SIZE] " if $count > $self->[BLOCK_COUNT] * $self->[BLOCK_SIZE];
    $self->[ITEM_COUNT] = $count;
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

    return undef unless $remove_length || @vals;

    # check for removal past end
    if( $offset > ($self->[ITEM_COUNT] - 1) ) {
        $remove_length = 0;
        $offset = $self->[ITEM_COUNT];
    }
    if( $remove_length > ($self->[ITEM_COUNT] - $offset) ) {
        $remove_length = $self->[ITEM_COUNT] - $offset;
    }

    #
    # embiggen to delta size if this would grow
    #
    my $new_size = $self->[ITEM_COUNT];
    $new_size -= $remove_length;
    if( $new_size < 0 ) {
        $new_size = 0;
    }
    $new_size += @vals;

    if( $new_size > $self->[BLOCK_SIZE] * $self->[BLOCK_COUNT] ) {
        $self->_embiggen( $new_size );
    }

    my $BLOCK_COUNT = $self->[BLOCK_COUNT];
    my $store       = $self->[DSTORE];
    my $blocks      = $self->[DATA];
    my $BLOCK_SIZE  = $self->[BLOCK_SIZE];

    $Yote::DEBUG = 1; #$self->[LEVEL] == 2;

    if( $self->[LEVEL] == 0 ) {
        $self->_setcount( $new_size );
        return map { $store->_xform_out($_) } splice @$blocks, $offset, $remove_length, map { $store->_xform_in($_) } @vals;
    }

    $store->_dirty( $store->[WEAK]{$self->[ID]}, $self->[ID] );

    my( @removed );
    while( @vals && $remove_length ) {
        push @removed, $self->FETCH( $offset );
        $self->STORE( $offset++, shift @vals );
        $remove_length--;
    }

    if( $remove_length ) {
        # can leave a vacuum
        my $block_idx = int( $offset / $BLOCK_SIZE );
        my $block_off = $offset % $BLOCK_SIZE;
        my $block     = $self->_getblock( $block_idx, 'C' );

        $self->db( "REMOVE (first) $remove_length", $block, \@vals, $offset, $remove_length, \@removed );

        my $can_remove = @$block - $block_off;
        if( $can_remove > $remove_length ) {
            $can_remove = $remove_length;
        }
        push @removed, splice @$block, $block_off, $can_remove;
        $remove_length -= $can_remove;

        $self->db( "REMOVE (AF) $remove_length", $block, \@vals, $offset, $remove_length, \@removed );
        #
        # If this is the last block, then things are done.
        # Otherwise we have to clean up the vacuum and remove
        # more things
        #
        if( $block_idx < int(($self->[ITEM_COUNT] - 1)/$BLOCK_SIZE) ) {

            my $vacuum = $BLOCK_SIZE - @$block;
            my $last_block = $block;

            $block_idx++;

            # got to last block? deal with the vacuum and you're done
            if( $block_idx == int(($self->[ITEM_COUNT] - 1)/$BLOCK_SIZE) ) {
                my $block = $self->_getblock( $block_idx );
                if( $block ) {
                    my $remove = $remove_length > @$block ? @$block : $remove_length;
                    if( $remove > 0 ) {
                        push @removed, splice @$block, 0, $remove;
                        $self->_setcount( $self->[ITEM_COUNT] - $remove );
                    }
                }
                if( $vacuum ) {
                    my @fill = splice( @$block, 0, $vacuum );
                    splice @$last_block, scalar(@$last_block), 0, @fill;
                    $self->_setcount( $self->[ITEM_COUNT] - $vacuum );
                }
                die "OHNSAKT REMMY" if $self->[ITEM_COUNT] != $new_size;
                #                $self->_setcount( $new_size );
                $self->db( "REMOVE (LAST) $remove_length, vacuum $vacuum", $block, \@vals, $offset, $remove_length, \@removed );
                return @removed;
            }

            # deleting whole blocks
            while( $remove_length >= $BLOCK_SIZE ) {
                my $block = $self->_getblock( $block_idx );
                if( $block ) {
                    push @removed, @$block;
                }
                else {
                    push @removed, (undef) x $BLOCK_SIZE;
                }
                splice @$blocks, $block_idx, 1;
                $remove_length -= $BLOCK_SIZE;
                $self->_setcount( $self->[ITEM_COUNT] - $BLOCK_SIZE );
                $self->db( "REMOVE (WHOLB) $remove_length, vacuum $vacuum", $block, \@vals, $offset, $remove_length, \@removed );
            }

            # not yet at last block? apply the vacuum to it until
            # you are
            while( $block_idx < int( ($self->[ITEM_COUNT]-1)/$BLOCK_SIZE) ) {
                my $block = $self->_getblock( $block_idx, 'C' );
                $self->db( "REMOVE (FUUR) $remove_length, vacuum $vacuum", $block, \@vals, $offset, $remove_length, \@removed );

                # oh, yeah, do the deleting here, too
                # forgot that for some dumb reason
                if( $remove_length ) {
                    push @removed, splice @$block, 0, $remove_length;
                    $remove_length = 0;
                }

                if( $vacuum ) {
                    my @fill = splice( @$block, 0, $vacuum );
                    splice @$last_block, scalar( @$last_block ), 0, @fill;
                    $last_block = $block;
                }
                $self->db( "REMOVE (AFTERD) $remove_length, vacuum $vacuum", $block, \@vals, $offset, $remove_length, \@removed );
                $block_idx++;
            }

            # must be the last block
            my $block = $self->_getblock( $block_idx );

            if( $block ) {
                $self->db( "REMOVE (ATLAST) $remove_length, vacuum $vacuum", $block, \@vals, $offset, $remove_length, \@removed );
                my $remove = $remove_length > @$block ? @$block : $remove_length;
                if( $remove ) {
                    push @removed, splice @$block, 0, $remove;
                }
                if( $vacuum ) {
                    splice @$last_block, scalar(@$last_block), 0, splice( @$block, 0, $vacuum );
                }
                $self->db( "REMOVE (mustlast) $remove_length <$remove>, vacuum $vacuum", $block, \@vals, $offset, $remove_length, \@removed );
            } else {
                $block = $self->_getblock( $block_idx, "C" );
            }
        } #not at end
        $self->_setcount( $new_size );
    } # has things to remove

    if( @vals ) {

        # can create a bubble pushing stuff to the end
        my $block_idx = int( $offset / $BLOCK_SIZE );
        my $block_off = $offset % $BLOCK_SIZE;
        my $block     = $self->_getblock( $block_idx, 'C' );

        $self->db("IN VALS at off $block_off", $block, \@vals, $offset, $remove_length );
        # insert into a partial block
        if( $block_off > 0 ) {
            my $insert_span = $BLOCK_SIZE - $block_off;
            if( $insert_span > @vals ) {
                $insert_span = @vals;
            }
            my $avail_span = @$block - $block_off;
            if( $avail_span > $insert_span ) {
                $avail_span = $insert_span;
            }

            if( $avail_span > 0 ) {
# HOW??? the sub block somehow has the same level
#                die "ARGS" if $self->[LEVEL] == tied( @$block )->[LEVEL];
                push @vals, splice @$block, $block_off, $avail_span;
                $self->_setcount( $self->[ITEM_COUNT] - $avail_span );
                $insert_span = $BLOCK_SIZE - $block_off;
                if( $insert_span > @vals ) {
                    $insert_span = @vals;
                }
                $self->db("BLOCKOFF>--1 <$insert_span>", $block, \@vals, $offset, $remove_length );
            }
            push @$block, splice @vals, 0, $insert_span;
            $self->_setcount( $self->[ITEM_COUNT] + $insert_span );

            $self->db("BLOCKOFF>0", $block, \@vals, $offset, $remove_length );
            $block_idx++;
        } #partial block

        # can insert whole blocks now
        while( @vals >= $BLOCK_SIZE ) {
            splice @$blocks, $block_idx, 0, undef;
            $block = $self->_getblock( $block_idx, 'C' );

            my @from_vals = splice @vals, 0, $BLOCK_SIZE;
            push @vals, @$block;
            splice @$block, 0, 0, @from_vals;
            $self->_setcount( $self->[ITEM_COUNT] + $BLOCK_SIZE );

            $self->db("WHOLE BLOCK $block_idx (NEWSIZE $new_size)", $block, \@vals, $offset, $remove_length );

            $block_idx++;

        }

        # now have partial blocks to push the bubble upwards
        while( @vals ) {
            my $LAST_BLK_IDX = int( ($new_size - 1) / $BLOCK_SIZE );
            $block = $self->_getblock( $block_idx, 'C' );

            if( @$block ) {
                $self->_setcount( $self->[ITEM_COUNT] - @$block ) if $LAST_BLK_IDX == $block_idx;
                push @vals, splice @$block, 0, scalar(@$block);

            }
            my $can_insert = $BLOCK_SIZE;
            if( $can_insert > @vals ) {
                $can_insert = @vals;
            }

            push @$block, splice @vals, 0, $can_insert;
            $self->_setcount( $self->[ITEM_COUNT] + $can_insert ) if $LAST_BLK_IDX == $block_idx;

            $self->db("PARTIAL <$can_insert>  $block_idx (offset $block_off)", $block, \@vals, $offset, $remove_length );

            $block_idx++;
        } #while vals
#        die "OHNSAKT ($self->[ITEM_COUNT] vs $new_size)" if $self->[ITEM_COUNT] != $new_size;
        #            $self->db("BEFOREFINAL $block_idx (offset $block_off)", $block, \@vals, $offset, $remove_length );

        # final block to push into
        #  $block = $self->_getblock( $block_idx, 'C' );
        #  splice @$block, 0, 0, @vals;
        #  $self->[ITEM_COUNT] += @vals;
        
        
        # $self->db("FINAL $block_idx (offset $block_off)", $block, \@vals, $offset, $remove_length );

        #                        $Yote::DEBUG2 = 0;
    } # has vals

    $self->_setcount( $new_size );
    
    return @removed;

} #SPLICE

sub EXTEND {
}

sub DESTROY {
    my $self = shift;
    delete $self->[DSTORE]->[WEAK]{$self->[ID]};
}

# --------------------------------------------------------------------------------

package Yote::Hash;

##################################################################################
# This module is used transparently by Yote to link hashes into its              #
# graph structure. This is not meant to  be called explicitly or modified.       #
##################################################################################

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
sub _freezedry {
    my $self = shift;
    my $r = $self->[DATA];
    join( "`",
          $self->[LEVEL],
          $self->[BUCKETS],
          $self->[SIZE],
          map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } $self->[LEVEL] ? @$r : %$r
      );
}

sub _reconstitute {
    my( $cls, $store, $id, $data ) = @_;
    my $hash = {};
    tie %$hash, $cls, $store, $id, @$data;
    return $hash;
}

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
        $store->_dirty( $store->[Yote::ObjStore::WEAK]{$self->[ID]}, $self->[ID] );
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
        $store->_dirty( $store->[Yote::ObjStore::WEAK]{$self->[ID]}, $self->[ID] );
        return $store->_xform_out( delete $data->{$key} );
    } else {
        my $hval = 0;
        foreach (split //,$key) {
            $hval = $hval*33 - ord($_);
        }
        $hval = $hval % $self->[BUCKETS];
        return $self->[DSTORE]->_fetch( $data->[$hval] )->DELETE( $key );
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
            my $hash = $self->[DSTORE]->_fetch( $hash_id );
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
            my $hash = $self->[DSTORE]->_fetch( $hash_id );
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
                    my $hash_id = $store->_new_id;
                    tie %$hash, 'Yote::Hash', $store, $hash_id, 0, $self->[BUCKETS]+1, 1, $key, $data->{$key};

                    $store->_store_weak( $hash_id, $hash );
                    $store->_dirty( $store->[Yote::ObjStore::WEAK]{$hash_id}, $hash_id );

                    $newhash[$hval] = $hash;
                    $newids[$hval] = $hash_id;
                }

            }
            $self->[DATA] = \@newids;
            $data = $self->[DATA];

            $store->_dirty( $store->[Yote::ObjStore::WEAK]{$self->[ID]}, $self->[ID] );

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
            $hash = $store->_fetch( $hash_id );
            my $tied = tied %$hash;
            $tied->STORE( $key, $val );
        } else {
            $hash = {};
            $hash_id = $store->_new_id;
            tie %$hash, 'Yote::Hash', $store, $hash_id, 0, $self->[BUCKETS]+1, 1, $key, $store->_xform_in( $val );
            $store->_store_weak( $hash_id, $hash );
            $store->_dirty( $store->[Yote::ObjStore::WEAK]{$hash_id}, $hash_id );
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
                my $hash = $self->[NEXT][2] || $store->_fetch( $nexthashid );
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

    delete $self->[DSTORE]->[Yote::ObjStore::WEAK]{$self->[ID]};
}

# --------------------------------------------------------------------------------

package Yote::Obj;

use strict;
use warnings;
no  warnings 'uninitialized';

use constant {
    ID          => 0,
    DATA        => 1,
    DSTORE      => 2,
};

#
# The string version of the yote object is simply its id. This allows
# object ids to easily be stored as hash keys.
#
use overload
    '""' => sub { shift->[ID] }, # for hash keys
    eq   => sub { ref($_[1]) && $_[1]->[ID] == $_[0]->[ID] },
    ne   => sub { ! ref($_[1]) || $_[1]->[ID] != $_[0]->[ID] },
    '=='   => sub { ref($_[1]) && $_[1]->[ID] == $_[0]->[ID] },
    '!='   => sub { ! ref($_[1]) || $_[1]->[ID] != $_[0]->[ID] },
    fallback => 1;

sub id {
    shift->[ID];
}

sub set {
    my( $self, $fld, $val ) = @_;

    my $inval = $self->[DSTORE]->_xform_in( $val );
    if( $self->[DATA]{$fld} ne $inval ) {
        $self->[DSTORE]->_dirty( $self, $self->[ID] );
    }

    unless( defined $inval ) {
        delete $self->[DATA]{$fld};
        return;
    }
    $self->[DATA]{$fld} = $inval;
    return $self->[DSTORE]->_xform_out( $self->[DATA]{$fld} );
} #set


sub get {
    my( $self, $fld, $default ) = @_;

    my $cur = $self->[DATA]{$fld};
    my $store = $self->[DSTORE];
    if( ! defined( $cur ) && defined( $default ) ) {
        if( ref( $default ) ) {
            # this must be done to make sure the reference is saved
            # for cases where the reference has not yet made it to the store of things to save
            $store->_dirty( $store->_get_id( $default ) );
        }
        $store->_dirty( $self, $self->[ID] );
        $self->[DATA]{$fld} = $store->_xform_in( $default );
    }
    return $store->_xform_out( $self->[DATA]{$fld} );
} #get


sub store {
    return shift->[DSTORE];
}

# -----------------------
#
#     Public Methods
# -----------------------
#
# Defines get_foo, set_foo, add_to_foolist, remove_from_foolist
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
            my $store = $self->[DSTORE];
            my $inval = $store->_xform_in( $val );
            $store->_dirty( $self, $self->[ID] ) if $self->[DATA]{$fld} ne $inval;
            unless( defined $inval ) {
                delete $self->[DATA]{$fld};
                return;
            }
            $self->[DATA]{$fld} = $inval;
            return $store->_xform_out( $self->[DATA]{$fld} );
        };
        use strict 'refs';
        goto &$AUTOLOAD;
    }
    elsif( $func =~ /:get_(.*)/ ) {
        my $fld = $1;
        no strict 'refs';
        *$AUTOLOAD = sub {
            my( $self, $init_val ) = @_;
            my $store = $self->[DSTORE];
            if( ! defined( $self->[DATA]{$fld} ) && defined($init_val) ) {
                if( ref( $init_val ) ) {
                    # this must be done to make sure the reference is saved for cases where the reference has not yet made it to the store of things to save
                    $store->_dirty( $init_val, $store->_get_id( $init_val ) );
                }
                $store->_dirty( $self, $self->[ID] );
                $self->[DATA]{$fld} = $store->_xform_in( $init_val );
            }
            return $store->_xform_out( $self->[DATA]{$fld} );
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
sub _freezedry {
    my $self = shift;
    join( "`", map { if( defined($_) ) { s/[\\]/\\\\/gs; s/`/\\`/gs; } $_ } %{$self->[DATA]} );
}

sub _reconstitute {
    my( $cls, $store, $id, $data ) = @_;
    my $obj = [$id,{@$data},$store];
    bless $obj, $cls;
    $store->_dirty( $obj, $id );
    $obj->_load;
    $obj;
}

sub DESTROY {
    my $self = shift;

    delete $self->[DSTORE][Yote::ObjStore::WEAK]{$self->[ID]};
}

1;

__END__

=head1 NAME

Yote - Persistant Perl container objects in a directed graph of lazilly
loaded nodes.

=head1 DESCRIPTION

This is for anyone who wants to store arbitrary structured state data and
doesn't have the time or inclination to write a schema or configure some
framework. This can be used orthagonally to any other storage system.

Yote only loads data as it needs too. It does not load all stored containers
at once. Data is stored in a data directory and is stored using the Data::RecordStore module. A Yote container is a key/value store where the values can be
strings, numbers, arrays, hashes or other Yote containers.

The entry point for all Yote data stores is the root node.
All objects in the store are unreachable if they cannot trace a reference
path back to this node. If they cannot, running compress_store will remove them.

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
    someobj  => $store->newobj( { foo => "Bar" }, 'yote - class' );
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
