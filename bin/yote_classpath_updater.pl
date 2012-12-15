#!/usr/bin/env perl

#
# Must have the yote server shut down to run this maintenance script.
# Usage : library_application_path_updater <list of paths to include>
#
use Yote::YoteRoot;
use Yote::ObjProvider;
use Yote::ConfigData;

my $var_dir = Yote::ConfigData->config( 'yote_var_dir' );
my $sqlitefile = "$var_dir/SQLite.yote.db";

Yote::ObjProvider::init( sqlitefile => $sqlitefile );
my $root = Yote::YoteRoot::fetch_root();
$root->set__application_lib_directories( [
					     keys %{ +{map { $_ => 1 } @{$root->get__application_lib_directories( [] )}, @ARGV} }
    ] );
print "Yote Classpaths now ".join("\n\t",@{$root->get__application_lib_directories()})."\n";
Yote::ObjProvider::stow_all();
