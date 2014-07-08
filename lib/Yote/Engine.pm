package Yote::Engine;

use strict;
use warnings;
no warnings 'uninitialized';

use IO::Handle;
use IO::Socket;
use JSON;

use Yote::ObjManager;
use Yote::ObjProvider;
use Yote::Root;

#
# Starts up a connection to the database, then opens a socket for
# other processes to talk to this one.
#
sub start {
    my $cfg = shift;
    die "Missing config in Engine" unless ref $cfg eq 'HASH';

    # TODO : set up database connection
    Yote::ObjProvider::init( $cfg );

    # TODO : rename fetch_root --> fetch
    my $root = Yote::Root::fetch();
    $root->_update_master_root( $cfg->{ root_account },
                                $cfg->{ root_password } );

    # TODO : stick additional classpaths in root obj
    #        and update the yote admin page to set those there

    until( my $socket = new IO::Socket::INET(
               Listen => 10, 
               # TODO : make sure there is an internal_port
               LocalPort => $cfg->{internal_port};
           ) ) 
    {
        if( $! =~ /Address already in use/i ) {
            print STDERR "Address '$cfg->{internal_port}' already in use. Retrying.\n";
            sleep( 5 );
        } else {
            die $!;
        }
    } # until connection established

    # TODO : end condition for shutdown
    while( my $conn = $self->{lsn}->accept ) {
        my $req = <$conn>;
        # TODO : check if json escapes all newlines

        eval {
            my $command = from_json( $req );

            my $app_id = $command->{ ai };
            my $app = Yote::ObjProvider::fetch( $app_id ) || $root;

            # TODO - move the translating of the data from base64 to the 
            #        server thread. Do as little work as possible here
            my $data = $command->{ d };

            #
            # A yote uesr can either be logged in, or be a 'guest' that is tokenized with
            # the token associated with that person's ip address
            #
            my $login       = $app->token_login( $command->{t}, undef, $command->{e} );

            #
            # The guest token is for clients that do not have a logged in user.
            # The token is stored with the IP address of the client and both
            # are used to verify the token.
            #
            my $guest_token =  $root->check_guest_token( $command->{e}{ REMOTE_ADDR }, $command->{gt} ) 
                || $root->guest_token( $command->{e}{ REMOTE_ADDR } );
            $command->{e}{GUEST_TOKEN} = $guest_token;

            #
            # Security check. This will trip if an object is requested by the client where the
            # client has not been given a reference to that object.
            #
            unless( Yote::ObjManager::allows_access( $obj_id, $app, $login, $guest_token ) ) {
                accesslog( "INVALID ACCCESS ATTEMPT for $obj_id from $command->{e}{ REMOTE_ADDR }" );
                die "Access Error";
            }
        #
        # The object in question that will have the action method run on it.
        #
        my $app_object = Yote::ObjProvider::fetch( $obj_id ) || $app;
        my $action     = $command->{a};

        #
        # set or adding to a list of the object may not be called directly on an object.
        #
        die "Access Error" if $action =~ /^([gs]et|add_(once_)?to_|remove_(all_)?from)_/; 

        #
        # If a user is logged in, that user will have an account associated with whatever
        # app this call is for. Find that.
        #
        my $account;
        if( $login ) {
            die "Access Error" if $login->get__is_disabled();
            $account = $app->__get_account( $login );
            die "Access Error" if $app->get_requires_validation() && ! $login->get__is_validated();
            die "Access Error" if $account->get__is_disabled() || $login->get__is_disabled();
            $account->set_login( $login ); # security measure to make sure login can't be overridden by a subclass of account
            $login->add_once_to__accounts( $account );
        }
        
        #
        # This is where the magic method call is done and the response generated.
        #
        my $ret = $app_object->$action( $data, $account, $command->{e} );
        
        #
        # Prepare the response object. It has the following parts :
        #    r - the response itself
        #    d - updates for dirty data
        #    err - if there was an exception, this contains the exception message.
        #
        $resp = { r =>  _obj_to_response( $ret, $login, $guest_token ) };

        #
        # This block checks to see if there are objects that the client has
        # a reference to that were updated since the client last communicated
        # with the server.
        #
        my $dirty_delta = Yote::ObjManager::fetch_dirty( $login, $guest_token );
        if( @$dirty_delta ) {
            my $dirty_data = {};
            for my $d_id ( @$dirty_delta ) {
                my $dobj = Yote::ObjProvider::fetch( $d_id );
                if( ref( $dobj ) eq 'ARRAY' ) {
                    $dirty_data->{$d_id} = { map { $_ => Yote::ObjProvider::xform_in( $dobj->[$_] ) } (0..$#$dobj) };
                } elsif( ref( $dobj ) eq 'HASH' ) {
                    $dirty_data->{$d_id} = { map { $_ => Yote::ObjProvider::xform_in( $dobj->{ $_ } ) } keys %$dobj };
                } else { # Yote::Obj
                    $dirty_data->{$d_id} = { map { $_ => $dobj->{DATA}{$_} } grep { $_ !~ /^_/ } keys %{$dobj->{DATA}} };
                }
                for my $val (values %{ $dirty_data->{$d_id} } ) {
                    # this registers the objects that were introduced via data structure to the client
                    if( index( $val, 'v' ) != 0 ) {
                        Yote::ObjManager::register_object( $val, $login ? $login->{ID} : $guest_token );
                    }
                }
            }
            $resp->{d} = $dirty_data;
        } #if there was a dirty delta
        }; #eval
        if( $@ ) {
            my $err = $@;
            print STDERR Data::Dumper->Dump(["ERRRR $@",$command]);
            $err =~ s/at \/\S+\.pm.*//s;
            errlog( "ERROR : $@" );
            iolog( "ERROR : $@" );
            $resp = { err => $err, r => '' };
        } #if error

        #
        # Save the state of the database completely.
        #
        Yote::ObjProvider::start_transaction();
        Yote::ObjProvider::stow_all();
        Yote::ObjProvider::flush_all_volatile();
        Yote::ObjProvider::commit_transaction();

        return to_json( $resp );

    } # until 

    exit;

} #start



#
# Converts scalar, yote object, hash or array to data for returning.
#
sub _obj_to_response {
    my( $to_convert, $login, $guest_token ) = @_;
    my $ref = ref($to_convert);
    my $use_id;
    if( $ref ) {
        my( $m, $d );
        if( $ref eq 'ARRAY' ) {
            my $tied = tied @$to_convert;
            if( $tied ) {
                $d = $tied->[1];
                $use_id = Yote::ObjProvider::get_id( $to_convert );
                for my $entry (@$d) {
                    next unless $entry;
                    if( index( $entry, 'v' ) != 0 ) {
                        Yote::ObjManager::register_object( $entry, $login ? $login->{ID} : $guest_token );
                    }
                }
            } else {
                $d = __transform_data_no_id( $to_convert, $login, $guest_token );
            }
        } 
        elsif( $ref eq 'HASH' ) {
            my $tied = tied %$to_convert;
            if( $tied ) {
                $d = $tied->[1];
                $use_id = Yote::ObjProvider::get_id( $to_convert );
                for my $entry (values %$d) {
                    next unless $entry;
                    if( index( $entry, 'v' ) != 0 ) {
                        Yote::ObjManager::register_object( $entry, $login ? $login->{ID} : $guest_token );
                    }
                }
            } else {
                $d = __transform_data_no_id( $to_convert, $login, $guest_token );
            }
        } 
        else {
            $use_id = Yote::ObjProvider::get_id( $to_convert );
            $d = { map { $_ => $to_convert->{DATA}{$_} } grep { $_ && $_ !~ /^_/ } keys %{$to_convert->{DATA}}};
            for my $vl (values %$d) {
                if( index( $vl, 'v' ) != 0 ) {
                    Yote::ObjManager::register_object( $vl, $login ? $login->{ID} : $guest_token );
                }
            }
            $m = Yote::ObjProvider::package_methods( $ref );
        }

        Yote::ObjManager::register_object( $use_id, $login ? $login->{ID} : $guest_token ) if $use_id;
        return $m ? { c => $ref, id => $use_id, d => $d, 'm' => $m } : { c => $ref, id => $use_id, d => $d };
    } # if a reference
    return "v$to_convert";
} #_obj_to_response

1;

__END__
