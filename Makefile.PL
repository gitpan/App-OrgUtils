
use strict;
use warnings;

use 5.010001;

use ExtUtils::MakeMaker 6.30;



my %WriteMakefileArgs = (
  "ABSTRACT" => "Some utilities for Org documents",
  "AUTHOR" => "Steven Haryanto <stevenharyanto\@gmail.com>",
  "BUILD_REQUIRES" => {},
  "CONFIGURE_REQUIRES" => {
    "ExtUtils::MakeMaker" => "6.30"
  },
  "DISTNAME" => "App-OrgUtils",
  "EXE_FILES" => [
    "bin/count-org-todos",
    "bin/list-org-todos",
    "bin/count-done-org-todos",
    "bin/list-org-anniversaries",
    "bin/count-undone-org-todos",
    "bin/dump-org-structure",
    "bin/list-org-headlines"
  ],
  "LICENSE" => "perl",
  "NAME" => "App::OrgUtils",
  "PREREQ_PM" => {
    "Data::Clone" => 0,
    "DateTime" => 0,
    "Lingua::EN::Numbers::Ordinate" => 0,
    "List::MoreUtils" => 0,
    "Log::Any" => 0,
    "Org::Dump" => 0,
    "Org::Parser" => "0.26",
    "Perinci::CmdLine" => "0.56",
    "experimental" => 0
  },
  "TEST_REQUIRES" => {
    "File::Spec" => 0,
    "IO::Handle" => 0,
    "IPC::Open3" => 0,
    "Test::More" => 0
  },
  "VERSION" => "0.20",
  "test" => {
    "TESTS" => "t/*.t"
  }
);


my %FallbackPrereqs = (
  "Data::Clone" => 0,
  "DateTime" => 0,
  "File::Spec" => 0,
  "IO::Handle" => 0,
  "IPC::Open3" => 0,
  "Lingua::EN::Numbers::Ordinate" => 0,
  "List::MoreUtils" => 0,
  "Log::Any" => 0,
  "Org::Dump" => 0,
  "Org::Parser" => "0.26",
  "Perinci::CmdLine" => "0.56",
  "Test::More" => 0,
  "experimental" => 0
);


unless ( eval { ExtUtils::MakeMaker->VERSION(6.63_03) } ) {
  delete $WriteMakefileArgs{TEST_REQUIRES};
  delete $WriteMakefileArgs{BUILD_REQUIRES};
  $WriteMakefileArgs{PREREQ_PM} = \%FallbackPrereqs;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
  unless eval { ExtUtils::MakeMaker->VERSION(6.52) };

WriteMakefile(%WriteMakefileArgs);



