
use strict;
use warnings;

use Module::Build 0.3601;


my %module_build_args = (
  'build_requires' => {
    'Module::Build' => '0.3601'
  },
  'configure_requires' => {
    'Module::Build' => '0.3601'
  },
  'dist_abstract' => 'Some utilities for Org documents',
  'dist_author' => [
    'Steven Haryanto <stevenharyanto@gmail.com>'
  ],
  'dist_name' => 'App-OrgUtils',
  'dist_version' => '0.07',
  'license' => 'perl',
  'module_name' => 'App::OrgUtils',
  'recommends' => {},
  'recursive_test_files' => 1,
  'requires' => {
    'Lingua::EN::Numbers::Ordinate' => '0',
    'Org::Parser' => '0.20',
    'Sub::Spec::CmdLine' => '0.30',
    'Test::More' => '0.96',
    'perl' => '5.010000'
  },
  'script_files' => [
    'bin/dump-org-structure',
    'bin/list-org-anniversaries',
    'bin/list-org-headlines',
    'bin/list-org-todos'
  ]
);


my $build = Module::Build->new(%module_build_args);

$build->create_build_script;
