pakcage Yote;

use vars qw($VERSION);
$VERSION = '0.02';

1;

__END__

=head1 NAME

Yote - a placeholder class for the packages below Yote.

=head1 SYNOPSIS


use Yote::WebAppServer;

my $server = new Yote::WebAppServer();

$server->start_server( port =E<gt> 8008,

=over 32

		       datastore => 'Yote::MysqlIO',
		       db => 'yote_db',
		       uname => 'yote_db_user',
		       pword => 'yote_db-password' );

=back

or

use Yote::WebAppServer;

$server->start_server( port =E<gt> 8008,

=over 32

		       datastore => 'Yote::SQLiteIO',
		       db => 'yote_db' );

=back

=cut
