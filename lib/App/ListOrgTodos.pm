package App::ListOrgTodos;

use 5.010;
use strict;
use warnings;
use Log::Any qw($log);

use App::ListOrgHeadlines qw(list_org_headlines);
use Data::Clone;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(list_org_todos);

our $VERSION = '0.18'; # VERSION

our %SPEC;

my $spec = clone($App::ListOrgHeadlines::SPEC{list_org_headlines});
$spec->{summary} = "List all todo items in all Org files";
delete $spec->{args}{todo};
$spec->{args}{done}{schema}[1]{default} = 0;
$spec->{args}{sort}{schema}[1]{default} = 'due_date';

$SPEC{list_org_todos} = $spec;
sub list_org_todos {
    my %args = @_;
    $args{done} //= 0;

    App::ListOrgHeadlines::list_org_headlines(%args, todo=>1);
}

1;
#ABSTRACT: List todo items in Org files

__END__

=pod

=encoding utf-8

=head1 NAME

App::ListOrgTodos - List todo items in Org files

=head1 VERSION

version 0.18

=head1 SYNOPSIS

 # See list-org-todos script

=head1 DESCRIPTION

=head1 FUNCTIONS

None are exported, but they are exportable.


None are exported by default, but they are exportable.

=head2 list_org_todos(%args) -> [status, msg, result, meta]

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
 won't pass the filter (it's still 10 days in the future, larger
than 7) but  will (warning period 14 days is already
passed by that time).

=item * B<files>* => I<array>

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

=item * B<sort> => I<any> (default: "due_date")

Specify sorting.

If string, must be one of 'dueI<date', '-due>date' (descending).

If code, sorting code will get [REC, DUEI<DATE, HL] as the items to compare,
where REC is the final record that will be returned as final result (can be a
string or a hash, if 'detail' is enabled), DUE>DATE is the DateTime object (if
any), and HL is the Org::Headline object.

=item * B<state> => I<str>

Only show todo items that have this state.

=item * B<time_zone> => I<str>

Will be passed to parser's options.

If not set, TZ environment variable will be picked as default.

=item * B<to_level> => I<int>

Only show headlines having this level as the maximum.

=item * B<today> => I<any>

Assume today's date.

You can provide Unix timestamp or DateTime object. If you provide a DateTime
object, remember to set the correct time zone.

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
