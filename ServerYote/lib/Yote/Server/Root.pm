package Yote::Server::Root;

use base 'Yote::Server::Obj';

sub _init {
    my $self = shift;
    $self->set__doesHave_Token2objs({});
    $self->set__mayHave_Token2objs({});
    $self->set__apps({});
    $self->set__token_timeslots([]);
    $self->set__token_timeslots_metadata([]);
    $self->set__token_mutex([]);
}

sub _log {
    Yote::Server::_log(shift);
}

sub _fetch_session {
    my( $self, $token ) = @_;
    my $slots = $self->get__token_timeslots();
    for( my $i=0; $i<@$slots; $i++ ) {
        if( my $session = $slots->[$i]{$token} ) {
            if( $i < $#$slots ) {
                # make sure this is in the most current 'boat'
                $slots->[0]{ $token } = $session;
            }
            return $session;
        }
    }
    
} #_fetch_sesion


sub _resetHasAndMay {
    my( $self, $tokens, $doesHaveOnly ) = @_;

    $self->{STORE}->lock( "_has_and_may_Token2objs" );
    my( @lists ) = $doesHaveOnly ? qw( doesHave ) : qw( doesHave mayHave );
    for ( @lists ) {
        my $item = "_${_}_Token2objs";
        my $token2objs = $self->_get( $item );
        for my $token (@$tokens) {
            delete $token2objs->{ $token };
        }
    }
    $self->{STORE}->unlock( "_has_and_may_Token2objs" );

} #_resetHasAndMay

sub _setHasAndMay {
    my( $self, $has, $may, $token ) = @_;

    $self->{STORE}->lock( "_has_and_may_Token2objs" );

    # has
    my $obj_data = $self->get__doesHave_Token2objs;
    for my $id (@$has) {
        next if index( $id, 'v' ) == 0 || $token eq '_';
        $obj_data->{$token}{$id} = Time::HiRes::time;
    }
    $self->{STORE}->_stow( $obj_data );
    
    # may
    $obj_data = $self->get__mayHave_Token2objs;
    for my $id (@$may) {
        next if index( $id, 'v' ) == 0 || $token eq '_';
        $obj_data->{$token}{$id} = Time::HiRes::time;
    }
    $self->{STORE}->_stow( $obj_data );
    
    $self->{STORE}->unlock( "_has_and_may_Token2objs" );
} #_setHasAndMay


sub _getMay {
    my( $self, $id, $token ) = @_;
    return 1 if index( $id, 'v' ) == 0;
    return 0 if $token eq '_';
    my $obj_data = $self->get__mayHave_Token2objs;
    $obj_data->{$token} && $obj_data->{$token}{$id};
}



sub _updates_needed {
    my( $self, $token, $outRes ) = @_;
    return [] if $token eq '_';

    my $obj_data = $self->get__doesHave_Token2objs()->{$token};
    my $store = $self->{STORE};
    my( @updates );
    for my $obj_id (@$outRes, keys %$obj_data ) {
        next if index( $obj_id, 'v' ) == 0;
        my $last_update_sent = $obj_data->{$obj_id};
        my $last_updated = $store->_last_updated( $obj_id );
        if( $last_update_sent <= $last_updated || $last_updated == 0 ) {
            unless( $last_updated ) {
                $store->{OBJ_UPDATE_DB}->put_record( $obj_id, [ Time::HiRes::time ] );
            }
            push @updates, $obj_id;
        }
    }
    \@updates;
} #_updates_needed

sub create_token {
    shift->_create_session->get__token;
}

sub _create_session {
    my $self = shift;
    my $tries = shift;

    if( $tries > 3 ) {
        die "Error creating token. Got the same random number 4 times in a row";
    }

    my $token = int( rand( 1_000_000_000 ) ); #TODO - find max this can be for long int
    
    # make the token boat. tokens last at least 10 mins, so quantize
    # 10 minutes via time 10 min = 600 seconds = 600
    # or easy, so that 1000 seconds ( ~ 16 mins )
    # todo - make some sort of quantize function here
    my $current_time_chunk         = int( time / 100 );  
    my $earliest_valid_time_chunk  = $current_time_chunk - 7;

    $self->{STORE}->lock( 'token_mutex' );


    #
    # A list of slot 'boats' which store token -> ip
    #
    my $slots     = $self->get__token_timeslots();

    #
    # a list of times. the list index of these times corresponds
    # to the slot 'boats'
    #
    my $slot_data = $self->get__token_timeslots_metadata();
    
    #
    # Check if the token is already used ( very unlikely ).
    # If already used, try this again :/
    #
    for( my $i=0; $i<@$slot_data; $i++ ) {
        return $self->_create_session( $tries++ ) if $slots->[ $i ]{ $token };
    }

    #
    # See if the most recent time slot is current. If it is behind, create a new current slot
    # create a new most recent boat.
    #
    my $session = $self->{STORE}->newobj( { 
        _token => $token } );
    if( $slot_data->[ 0 ] == $current_time_chunk ) {
        $slots->[ 0 ]{ $token } = $session;
    } else {
        unshift @$slot_data, $current_time_chunk;
        unshift @$slots, { $token => $session };
    }
    

    #
    # remove this token from old boats so it doesn't get purged
    # when in a valid boat.
    #
    for( my $i=1; $i<@$slot_data; $i++ ) {
        delete $slots->[$i]{ $token };
    }

    #
    # Purge tokens in expired boats.
    #
    my @to_remove;
    while( @$slot_data ) {
        if( $slot_data->[$#$slot_data] < $earliest_valid_time_chunk ) {
            pop @$slot_data;
            my $old = pop @$slots;
            push @to_remove, keys %$old;
        } else {
            last;
        }
    }

    if( @to_remove ) {
        $self->_resetHasAndMay( \@to_remove );
    }
    
    $self->{STORE}->unlock( 'token_mutex' );
    
    return $session;

} #_create_session

sub _destroy_session {
    my( $self, $token ) = @_;
    my $slots = $self->get__token_timeslots();
    for( my $i=0; $i<@$slots; $i++ ) {
        delete $slots->[$i]{ $token };
    }

    $self->_resetHasAndMay( [$token] );
    1;
} #_destroy_session

#
# Returns the app and possibly a logged in account
#
sub fetch_app {
    my( $self, $app_name ) = @_;
    my $apps = $self->get__apps;
    my $app  = $apps->{$app_name};
    unless( $app ) {
        eval("require $app_name");
        if( $@ ) {
            # TODO - have/use a good logging system with clarity and stuff
            # warnings, errors, etc
            _log( "App '$app_name' not found $@" );
            return undef;
        }
        _log( "Loading app '$app_name'" );
        $app = $app_name->_new( $self->{STORE} );
        $apps->{$app_name} = $app;
    }
    
    return $app, $self->{SESSION} ? $self->{SESSION}->get_acct : undef;
} #fetch_app

sub fetch_root {
    return shift;
}

sub init_root {
    my $self = shift;
    my $session = $self->{SESSION} || $self->_create_session;
    my $token = $session->get__token;
    $self->_resetHasAndMay( [ $token ], 'doesHaveOnly' );
    return $self, $token;
}

sub fetch {
    my( $self, @ids ) = @_;
    
    $self->{SESSION} && ( my $token = $self->{SESSION}->get__token ) || return;
    
    my $mays = $self->get__mayHave_Token2objs;
    my $may = $self->get__mayHave_Token2objs()->{$token};
    my $store = $self->{STORE};

    my @ret = map { $store->fetch($_) }
      grep { ! ref($_) && $may->{$_}  }
    @ids;
    die "Invalid id(s) ".join(",",grep { !ref($_) && !$may->{$_} } @ids) unless @ret == @ids;
    @ret;
} #fetch

# while this is a non-op, it will cause any updated contents to be 
# transfered to the caller automatically
sub update {

}

# ------- END Yote::Server::Root

1;
