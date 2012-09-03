#!/usr/bin/env perl

#
# Must have the yote server shut down to run this maintenance script.
# Usage : library_application_path_updater <list of paths to include>
#
use common::sense;
use Yote::YoteRoot;
use Yote::ObjProvider;


Yote::ObjProvider::init( sqlitefile => '/usr/local/yote/data/SQLite.yote.db' );
my $root = Yote::YoteRoot::fetch_root();
$root->set__application_lib_directories( [
    keys %{ +{map { $_ => 1 } @{$root->get__application_lib_directories( [] )}, @ARGV} }
    ] );
say "Yote Classpaths now ".join("\n\t",@{$root->get__application_lib_directories()})."\n";
Yote::ObjProvider::stow_all();
