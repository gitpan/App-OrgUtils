
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  "build_requires" => {
    "Module::Build" => "0.3601"
  },
  "configure_requires" => {
    "Module::Build" => "0.3601"
  },
  "dist_abstract" => "Some utilities for Org documents",
  "dist_author" => [
    "Steven Haryanto <stevenharyanto\@gmail.com>"
  ],
  "dist_name" => "App-OrgUtils",
  "dist_version" => "0.17",
  "license" => "perl",
  "module_name" => "App::OrgUtils",
  "recommends" => {},
  "recursive_test_files" => 1,
  "requires" => {
    "Data::Clone" => 0,
    "DateTime" => 0,
    "Lingua::EN::Numbers::Ordinate" => 0,
    "List::MoreUtils" => 0,
    "Log::Any" => 0,
    "Org::Dump" => 0,
    "Org::Parser" => "0.26",
    "Perinci::CmdLine" => "0.56",
    "perl" => "5.010001"
  },
  "script_files" => [
    "bin/dump-org-structure",
    "bin/list-org-todos",
    "bin/list-org-anniversaries",
    "bin/list-org-headlines",
    "bin/count-done-org-todos",
    "bin/count-org-todos",
    "bin/count-undone-org-todos"
  ]
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
