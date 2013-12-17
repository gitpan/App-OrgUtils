package App::OrgUtils;

use 5.010;
use strict;
use warnings;
use Log::Any '$log';

use Org::Parser;

our $VERSION = '0.20'; # VERSION

sub _load_org_files_with_cache {
    require Cwd;
    require Digest::MD5;

    my ($files, $cache_dir, $opts0) = @_;
    $files or die "Please specify files";

    my $orgp = Org::Parser->new;
    my %docs;
    for my $file (@$files) {
        my $cf;
        if ($cache_dir) {
            my $afile = Cwd::abs_path($file) or die "Can't find $file";
            my $afilel = $afile; $afilel =~ s!.+/!!;
            $cf = "$cache_dir/$afilel.".Digest::MD5::md5_hex($afile).
                ".storable";
            $log->debug("Parsing file $file (cache file $cf) ...");
        } else {
            $log->debug("Parsing file $file ...");
        }

        my $opts = { %{$opts0 // {}} };
        $opts->{cache_file} = $cf if $cf;
        $docs{$file} = $orgp->parse_file($file, $opts);
    }

    %docs;
}

1;
#ABSTRACT: Some utilities for Org documents

__END__

=pod

=encoding UTF-8

=head1 NAME

App::OrgUtils - Some utilities for Org documents

=head1 VERSION

version 0.20

=head1 DESCRIPTION

This distribution includes a few modules (scripts) for dealing with Org
documents; some originally created as examples/demos for L<Org::Parser>.

=head1 SEE ALSO

L<Org::Parser>

=head1 HOMEPAGE

Please visit the project's homepage at L<https://metacpan.org/release/App-OrgUtils>.

=head1 SOURCE

Source repository is at L<https://github.com/sharyanto/perl-App-OrgUtils>.

=head1 BUGS

Please report any bugs or feature requests on the bugtracker website L<https://rt.cpan.org/Public/Dist/Display.html?Name=App-OrgUtils>

When submitting a bug or request, please include a test-file or a
patch to an existing test-file that illustrates the bug or desired
feature.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
