#!/usr/bin/perl

use strict;

use warnings;

use Yote;
use Yote::AppRoot;

use File::Temp qw/ :mktemp /;
use File::Spec::Functions qw( catdir updir );
use Test::More; # tests => 3;
use Test::Pod;

use Carp;
$SIG{ __DIE__ } = sub { Carp::confess( @_ ) };

BEGIN {
    for my $class (qw/AppRoot/) {
        use_ok( "Yote::$class" ) || BAIL_OUT( "Unable to load Yote::$class" ); 
   }
}


# -----------------------------------------------------
#               init
# -----------------------------------------------------

my( $fh, $name ) = mkstemp( "/tmp/SQLiteTest.XXXX" );
$fh->close();

my %arg_hash = (
    datastore      => 'Yote::SQLiteIO',
    store          => $name,
    );

$arg_hash{ smtp_smtp }  = 'localhost' || Yote::_ask( "SMPT Host", undef, 'localhost' );
$arg_hash{ smtp_port }  = 25 || Yote::_ask( "SMPT Port", undef, 25 );
$arg_hash{ smtp_auth }  = 'PLAIN' || Yote::_ask( "SMPT Authentication Method", ['LOGIN','PLAIN','CRAM-MD5','NTLM'], 'PLAIN' );
if( $arg_hash{ smtp_auth } eq 'NTLM' ) {
    $arg_hash{ smtp_authdomain }  = Yote::_ask( "NTML Auth Domain" );
}
elsif( $arg_hash{ smtp_auth } eq 'LOGIN' ) {
    $arg_hash{ smtp_auth_encoded }  = Yote::_ask( "Should the LOGIN protocoll assume authid and authpwd are already base64 encoded?", ['Yes','No' ],  'No' );
    $arg_hash{ smtp_auth_encoded } = $arg_hash{ smtp_auth_encoded } ? 1 : 0;
}
if( $arg_hash{ smtp_auth } eq 'PLAIN' ) {
    $arg_hash{ smtp_auth } = '';
}
else {
    $arg_hash{ smtp_authid }  = Yote::_ask( "Auth ID" );
    $arg_hash{ smtp_authpwd } = Yote::_ask( "Auth Password" );
}
$arg_hash{ smtp_TLS_allowed } = 'No' || Yote::_ask( "Should TLS ( SSL encrypted connection ) be used ", ['Yes','No'], 'No' );
$arg_hash{ smtp_TLS_allowed } = $arg_hash{ smtp_TLS_allowed } eq 'Yes' ? 1 : 0;
$arg_hash{ smtp_TLS_required } = 'No' || Yote::_ask( "Must TLS ( SSL encrypted connection ) be used", ['Yes','No'], 'No' );
$arg_hash{ smtp_TLS_required } = $arg_hash{ smtp_TLS_required } eq 'Yes' ? 1 : 0;

Yote::ObjProvider::init( %arg_hash );
Yote::IO::Mailer::init( %arg_hash );

my $db = $Yote::ObjProvider::DATASTORE->database();
test_suite( $db );
done_testing();

unlink( $name );

exit( 0 );

sub test_suite {
    my $root = Yote::YoteRoot->fetch_root();
    my $app = new Yote::AppRoot( {
	requires_validation => 1,
	login_email_from    => 'yote@localhost',
	host_name           => 'localhost',
				 } );
    my $to = 'wolf@localhost' || Yote::_ask( "What email should I use to test?" );
    my $o_pw = 'passwoid';
    my $h = 'Haendel';
    my $res = $app->create_login( {
	h => $h,
	e => $to,
	p => $o_pw,
				  }, undef, { REMOTE_ADDR => 127.0.0.1 } );
    my $login = $res->{l};
    my $vt = $login->get__validation_token();

    my $got_vt;
    if( 1 ) {
	print "What is the validation token sent in the email?";
	$got_vt = <STDIN>;
	chomp( $got_vt );
	is( $got_vt, $vt, "validation token is correct" );
    } else { $got_vt = $vt; }

    ok( ! $login->get__is_validated(), "not yet validated" );
    $app->validate( "123$got_vt" );
    ok( ! $login->get__is_validated(), "still not yet validated" );
    $app->validate( $got_vt );
    ok( $login->get__is_validated(), "is now validated" );

    # password recovery
    $app->recover_password( $to );
    my $rt = $login->get__recovery_token();

    my $got_rt;
    if( 1 ) {
	print "What is the validation token sent in the email?";
	my $got_rt = <STDIN>;
	chomp( $got_rt );
	is( $got_rt, $rt, "recovery token is correct" );
    } else {
	$got_rt = $rt;
    }
    my $new_pw = 'newwoid';

    my $l = $root->login( { h => $h, p => $o_pw } );
    is( ref($l), 'HASH', "Got password response" );
    is( $l->{l}, $login, "Old Password still works" );

    eval {
	$app->recovery_reset_password( { p => $new_pw, t => "213$rt" } );
    };
    like( $@, qr/Recovery Link Expired or not valid/, "unable to recover with wrong token" );
    $l = $root->login( { h => $h, p => $o_pw } );
    is( ref($l), 'HASH', "Got response for old password" );
    is( $l->{l}, $login, "Old Password still works" );

    eval {
	$root->login( { h => $h, p => $new_pw } );
    };
    like( $@, qr/incorrect login/, "new password should not be set" );

    my $x = $app->recovery_reset_password( { p => $new_pw, t => $rt } );
    $l = $root->login( { h => $h, p => $new_pw } );
    is( ref($l), 'HASH', "Got response for new password" );
    is( $l->{l}, $login, "New Password now works" );
    

} #test_suite
