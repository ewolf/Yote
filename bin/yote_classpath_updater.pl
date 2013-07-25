#!/usr/bin/env perl

#
# Must have the yote server shut down to run this maintenance script.
# Usage : library_application_path_updater <list of paths to include>
#
use Yote;
use Yote::YoteRoot;
use Yote::ObjProvider;
use Yote::ConfigData;

use Data::Dumper;

my $args = Yote::get_args( allow_multiple_commands => 1 );
Yote::ObjProvider::init( %{ $args->{config} } );

my @paths = @{ $args->{ commands } };

my $root = Yote::YoteRoot::fetch_root();
$root->set__application_lib_directories(
    [
     keys %{ +{map { $_ => 1 } @{$root->get__application_lib_directories( [] )}, @paths} }
    ] );
print "Yote Classpaths now ".join("\n\t",@{$root->get__application_lib_directories()})."\n";

Yote::ObjProvider::start_transaction();
Yote::ObjProvider::stow_all();
Yote::ObjProvider::flush_all_volatile();
Yote::ObjProvider::commit_transaction();

