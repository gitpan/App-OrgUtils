package App::ListOrgTodos;

our $DATE = '2015-01-03'; # DATE
our $VERSION = '0.23'; # VERSION

use 5.010;
use strict;
use warnings;
use Log::Any qw($log);

use App::ListOrgHeadlines qw(list_org_headlines);
use Perinci::Sub::Util qw(gen_modified_sub);

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(list_org_todos);

our %SPEC;

gen_modified_sub(
    output_name => 'list_org_todos',
    summary     => 'List all todo items in all Org files',

    base_name   => 'App::ListOrgHeadlines::list_org_headlines',
    remove_args => ['todo'],
    modify_args => {
        done => sub { my $as = shift; $as->{schema}[1]{default} = 0 },
        sort => sub { my $as = shift; $as->{schema}[1]{default} = 'due_date' },
    },
    modify_meta => sub {
        my $meta = shift;
        $meta->{"x.dist.zilla.plugin.rinci.wrap.wrap_args"} = {validate_args=>0, validate_result=>0}; # don't bother checking arguments, they will be checked in list_org_headlines()
    },
    output_code => sub {
        my %args = @_;

        $args{done} //= 0;

        App::ListOrgHeadlines::list_org_headlines(%args, todo=>1);
    },
);

1;
# ABSTRACT: List all todo items in all Org files

__END__

=pod

=encoding UTF-8

=head1 NAME

App::ListOrgTodos - List all todo items in all Org files

=head1 VERSION

This document describes version 0.23 of App::ListOrgTodos (from Perl distribution App-OrgUtils), released on 2015-01-03.

=head1 SYNOPSIS

 # See list-org-todos script

=head1 DESCRIPTION

=head1 FUNCTIONS

None are exported, but they are exportable.


=head2 list_org_todos(%args) -> [status, msg, result, meta]

List all todo items in all Org files.

Arguments ('*' denotes required arguments):

=over 4

=item * B<cache_dir> => I<str>

Cache Org parse result.

Since Org::Parser can spend some time to parse largish Org files, this is an
option to store the parse result. Caching is turned on if this argument is set.

=item * B<detail> => I<bool> (default: 0)

Show details instead of just titles.

=item * B<done> => I<bool> (default: 0)

Only show todo items that are done.

=item * B<due_in> => I<int>

Only show todo items that are (nearing|passed) due.

If value is not set, then will use todo item's warning period (or, if todo item
does not have due date or warning period in its due date, will use the default
14 days).

If value is set to something smaller than the warning period, the todo item will
still be considered nearing due when the warning period is passed. For example,
if today is 2011-06-30 and due_in is set to 7, then todo item with due date
<2011-07-10 > won't pass the filter (it's still 10 days in the future, larger
than 7) but <2011-07-10 Sun +1y -14d> will (warning period 14 days is already
passed by that time).

=item * B<files>* => I<array[str]>

=item * B<from_level> => I<int> (default: 1)

Only show headlines having this level as the minimum.

=item * B<group_by_tags> => I<bool> (default: 0)

Whether to group result by tags.

If set to true, instead of returning a list, this function will return a hash of
lists, keyed by tag: {tag1: [hl1, hl2, ...], tag2: [...]}. Note that some
headlines might be listed more than once if it has several tags.

=item * B<has_tags> => I<array>

Only show headlines that have the specified tags.

=item * B<lacks_tags> => I<array>

Only show headlines that don't have the specified tags.

=item * B<priority> => I<str>

Only show todo items that have this priority.

=item * B<sort> => I<str|code> (default: "due_date")

Specify sorting.

If string, must be one of 'due_date', '-due_date' (descending).

If code, sorting code will get [REC, DUE_DATE, HL] as the items to compare,
where REC is the final record that will be returned as final result (can be a
string or a hash, if 'detail' is enabled), DUE_DATE is the DateTime object (if
any), and HL is the Org::Headline object.

=item * B<state> => I<str>

Only show todo items that have this state.

=item * B<time_zone> => I<str>

Will be passed to parser's options.

If not set, TZ environment variable will be picked as default.

=item * B<to_level> => I<int>

Only show headlines having this level as the maximum.

=item * B<today> => I<int|obj>

Assume today's date.

You can provide Unix timestamp or DateTime object. If you provide a DateTime
object, remember to set the correct time zone.

=back

Returns an enveloped result (an array).

First element (status) is an integer containing HTTP status code
(200 means OK, 4xx caller error, 5xx function error). Second element
(msg) is a string containing error message, or 'OK' if status is
200. Third element (result) is optional, the actual result. Fourth
element (meta) is called result metadata and is optional, a hash
that contains extra information.

Return value:  (any)
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

perlancar <perlancar@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2015 by perlancar@cpan.org.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
