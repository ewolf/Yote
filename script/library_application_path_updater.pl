use strict;

#
# Must have the yote server shut down to run this maintenance script.
# Usage : library_application_path_updater <list of paths to include>
#

use Yote::ObjProvider;
use Yote::YoteRoot;

Yote::ObjProvider::init( sqlitefile => '/usr/local/yote/data/SQLite.yote.db' );
my $root = Yote::YoteRoot::fetch_root();
$root->set__application_lib_directories( [
    keys %{ +{map { $_ => 1 } @{$root->get__application_lib_directories( [] )}, @ARGV} }
    ] );
Yote::ObjProvider::stow_all();
