#!/usr/bin/perl

use strict;
use warnings;
no warnings 'numeric';

use Yote;
use Data::Dumper;

my $db_dir = shift @ARGV || '/opt/yote/DATA_STORE';
my $store = Yote::open_store( $db_dir );

show( $store->fetch_root->{ID} );

"how about delete, move, add, purge?";


print ">";

while( my $in = <STDIN> ) {
    chomp $in;
    interpret( $in );
    print "\n>";
}

exit;

sub interpret {
    my $cmd = shift;

    if( $cmd > 0 ) {
        show( $cmd );
    } #SHOW

    elsif( $cmd =~ /^\s*PURGE/i ) {
        print "\nrunning purger\n";
        print `du $db_dir`;
        print "\n";
        $store->run_purger;
        print "\ndone running purger\n";
        print `du $db_dir`;
        print "\n";
    } #PURGE

    elsif( $cmd =~ /^\s*STOW/i ) {
        print "Stowing all\n";
        $store->stow_all;
        print "Done\n";
    } #STOW

    elsif( $cmd =~ /^\s*EXIT/i ) {
        if( $store->dirty_count > 0 ) {
            print "About to exit. There are things not saved. Proceed without saving (yes/N)? ";
            my $yn = <STDIN>;
            chomp $yn;
            if( $yn eq 'yes' ) {
                exit;
            }
            print "Exit aborted\n";
        } else {
            exit;
        }
    } #STOW

    elsif( $cmd =~ /^\s*DELETE\s+(\d+)\s+(\S+)/ ) {
        my( $from_id, $from_field ) = ( $1, $2 );

        my $obj = $store->fetch( $from_id );
        my $r = ref( $obj );
        if( $r eq 'ARRAY' ) {
            unless( $from_field > 0 || $from_field eq '0' ) {
                print "object $from_id is an array. Field must be numeric. Doing nothing\n";
                return;
            }
            splice @$obj, $from_field, 1;
            print "Removed index '$from_field' from list at $from_id.\n";
        }
        elsif( $r eq 'HASH' ) {
            delete $obj->{$from_field};
            print "Removed field '$from_field' from hash at $from_id.\n";
        } else {
            delete $obj->{DATA}{$from_field};
            $store->_dirty( $obj, $from_id );
            print "Removed field '$from_field' from object at $from_id.\n";
        }
    } #DELETE

    elsif( $cmd =~ /^\s*ADD(LIST|OBJ|HASH|VAL|REF)\s+(\d+)\s+(\S+)(\s+(.*))?/ ) {
        my( $type, $to_id, $to_field, $value ) = ( $1, $2, $3, $5 );
        my $to_obj = $store->fetch( $to_id );
        my $to_r = ref( $to_obj );
        if( $to_r eq 'ARRAY' ) {
            unless( $to_field > 0 || $to_field eq '0' ) {
                print "$to_id is an array. Field must be numeric. Doing nothing\n";
                return;
            }
        } elsif( $to_r eq 'HASH' ) {
            if( defined $to_obj->{$to_field} ) {
                print "$to_id is an hash and there is already a value at $to_field. Doing nothing\n";
                return;
            }
        } elsif( defined( $to_obj->{DATA}{$to_field} ) ) {
            print "$to_id is an object and there is already a value at $to_field. Doing nothing\n";
            return;
        }

        if( $type eq 'REF' ) {
            # don't need to load the reference, just check it
            if( $value == 0 ) {
                print "Reference must be numeric\n";
                return;
            }
            unless( $store->has_id( $value ) ) {
                print "Reference $value not found.\n";
                return;
            }
            
            if( $to_r eq 'ARRAY' ) {
                my $tied = tied @$to_obj;
                splice @{$tied->[1]}, $to_field, 0, $value;
                print "Added reference $value to list $to_id at field $to_field\n";
            } elsif( $to_r eq 'HASH' ) {
                my $tied = tied %$to_obj;
                $tied->[1]->{$to_field} = $value;
                print "Added reference $value to hash $to_id at field $to_field\n";
            } else {
                $to_obj->{DATA}{$to_field} = $value;
                print "Added reference $value to object $to_id at field $to_field\n";
            }
            $store->_dirty( $to_obj, $to_id );
            return;
        }

        if( $type eq 'LIST' ) {
            $value = [];
        } elsif( $type eq 'HASH' ) {
            $value = {};
        } elsif( $type eq 'OBJ' ) {
            if( $value ) {
                eval("use $value");
                if( $@ ) {
                    print "Error instantiating object of $value : $@. Doing nothing\n";
                    return;
                }
            }
            $value = $store->newobj({},$value); #value is class here
        }

        if( $to_r eq 'ARRAY' ) {
            splice @$to_obj, $to_field, 0, $value;
            print "Added $value to list $to_id at field $to_field\n";
        } elsif( $to_r eq 'HASH' ) {
            $to_obj->{$to_field} = $value;
            print "Added $value to hash $to_id at field $to_field\n";
        } else {
            $to_obj->set( $to_field, $value );
            print "Added $value to object $to_id at field $to_field\n";
        }

    } #ADD

    elsif( $cmd =~ /^\s*MOVE\s+(\d+)\s+(\S+)\s+(\d+)\s+(\S+)/ ) {
        my( $from_id, $from_field, $to_id, $to_field ) = ( $1, $2, $3, $4 );
        my $to_obj = $store->fetch( $to_id );
        my $to_r = ref( $to_obj );

        if( $to_r eq 'ARRAY' ) {
            unless( $to_field > 0 || $to_field eq '0' ) {
                print "object $to_id is an array. Field must be numeric. Doing nothing\n";
                return;
            }
        }
        elsif( $to_r eq 'HASH' ) {
            if( defined($to_obj->{$to_field}) ) {
                print "Hash at $to_id aready has a value in field '$to_field'. Doing nothing\n";
                return;
            }
        } else {
            if( defined($to_obj->{DATA}{$to_field}) ) {
                print "Object at $to_id aready has a value in field '$to_field'. Doing nothing\n";
                return;
            }
        }

        my $from_obj = $store->fetch( $from_id );
        my $from_r = ref( $from_obj );
        my $from_val;
        if( $from_r eq 'ARRAY' ) {
            unless( $from_field > 0 || $from_field eq '0' ) {
                print "object $from_id is an array. Field must be numeric. Doing nothing\n";
                return;
            }
            my $tied = tied @$from_obj;
            $from_val = splice @{$tied->[1]}, $from_field, 1;
        }
        elsif( $from_r eq 'HASH' ) {
            my $tied = tied %$from_obj;
            $from_val = delete $tied->[1]->{$from_field};
        }
        else {
            $from_val = delete $from_obj->{DATA}{$from_field};
        }
        $store->_dirty( $from_obj, $from_id );

        if( $to_r eq 'ARRAY' ) {
            my $tied = tied @$to_obj;
            splice @{$tied->[1]}, $to_field, 0, $from_val;
            print "Moved '$from_val' from '$from_id' field '$from_field' to list '$to_id' field '$to_field'\n";
        }
        elsif( $to_r eq 'HASH' ) {
            my $tied = tied @$to_obj;
            $tied->[1]{$to_field} = $from_val;
            print "Moved '$from_val' from '$from_id' field '$from_field' to hash '$to_id' field '$to_field'\n";
        } else {
            $to_obj->{DATA}{$to_field} = $from_val;
            print "Moved '$from_val' from '$from_id' field '$from_field' to object '$to_id' field '$to_field'\n";
        }
        $store->_dirty( $to_obj, $to_id );

    } #MOVE
    else {

    }
} #interpret

sub show {
    my $id = shift;
    my $obj = $store->fetch( $id );
    unless( $obj ) {
        print "Nothing found for id $id\n";
        return;
    }
    my $r = ref( $obj );
    if( $r eq 'HASH' ) {
        print "$id is hash with ".scalar(keys %$obj)." keys\n";
        my $count = 0;
        for my $key (sort keys %$obj) {
            print "\t$key => ".$store->_xform_in( $obj->{$key} )."\n";
            if( ++$count > 100 ) {
                $count = 0;
                print " .... more ..\n>";
                my $in = <STDIN>;
                chomp $in;
                if( $in =~ /\S/ ) {
                    interpret( $in );
                    return;
                }
            }
        }
    }
    elsif( $r eq 'ARRAY' ) {
        print "$id is array with ".scalar(@$obj)." elements\n";
        my $count = 0;
        for( my $i=0; $i<@$obj; $i++ ) {
            print "\t$i) ".$store->_xform_in( $obj->[$i] )."\n";
            if( ++$count > 100 ) {
                $count = 0;
                print " .... more ..\n>";
                my $in = <STDIN>;
                chomp $in;
                if( $in > 0 ) {
                    show( $in );
                    return;
                }
            }
        }
    }
    else {
        print "$id is $r\n\t".join("\n\t",map { "$_ => $obj->{DATA}{$_}" }
                                 keys %{$obj->{DATA}} )."\n";
    }
}





__END__

a command line explorer for a yote database.

Can view and edit.
