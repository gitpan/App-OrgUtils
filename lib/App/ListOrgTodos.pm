package App::ListOrgTodos;

use 5.010;
use strict;
use warnings;
use Log::Any qw($log);

use App::ListOrgHeadlines qw(list_org_headlines);
use Data::Clone;
use DateTime;
use Org::Parser;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(list_org_todos);

our $VERSION = '0.13'; # VERSION

our %SPEC;

my $spec = clone($App::ListOrgHeadlines::SPEC{list_org_headlines});
$spec->{summary} = "List all todo items in all Org files";
delete $spec->{args}{todo};
$spec->{args}{done}[1]{default} = 0;
$spec->{args}{done}[1]{sort} = 'due_date';

$SPEC{list_org_todos} = $spec;
sub list_org_todos {
    my %args = @_;
    $args{done} //= 0;

    App::ListOrgHeadlines::list_org_headlines(%args, todo=>1);
}

1;
#ABSTRACT: List todo items in Org files


=pod

=head1 NAME

App::ListOrgTodos - List todo items in Org files

=head1 VERSION

version 0.13

=head1 SYNOPSIS

 # See list-org-todos script

=head1 DESCRIPTION

=head1 FUNCTIONS

None are exported, but they are exportable.

=head1 FUNCTIONS


=head2 list_org_todos(%args) -> [status, msg, result, meta]

List all todo items in all Org files.

Arguments ('*' denotes required arguments):

=over 4

=item * B<detail> => I<bool> (default: 0)

Show details instead of just titles.

=item * B<done> => I<bool> (default: 0)

Filter todo items that are done.

=item * B<due_in> => I<int>

Filter todo items which is due in this number of days.

Note that if the todo's due date has warning period and the warning period is
active, then it will also pass this filter irregardless. Example, if today is
2011-06-30 and due_in is set to 7, then todo with due date  won't
pass the filter but  will (warning period 14 days is
already active by that time).

=item * B<files>* => I<array>

=item * B<from_level> => I<int> (default: 1)

Filter headlines having this level as the minimum.

=item * B<group_by_tags> => I<bool> (default: 0)

Whether to group result by tags.

If set to true, instead of returning a list, this function will return a hash of
lists, keyed by tag: {tag1: [hl1, hl2, ...], tag2: [...]}. Note that some
headlines might be listed more than once if it has several tags.

=item * B<has_tags> => I<array>

Filter headlines that have the specified tags.

=item * B<lacks_tags> => I<array>

Filter headlines that don't have the specified tags.

=item * B<priority> => I<str>

Filter todo items that have this priority.

=item * B<sort> => I<code|str> (default: "due_date")

Specify sorting.

If string, must be one of 'dueB<date', '-due>date' (descending).

If code, sorting code will get [REC, DUEB<DATE, HL] as the items to compare,
where REC is the final record that will be returned as final result (can be a
string or a hash, if 'detail' is enabled), DUE>DATE is the DateTime object (if
any), and HL is the Org::Headline object.

=item * B<state> => I<str>

Filter todo items that have this state.

=item * B<time_zone> => I<str>

Will be passed to parser's options.

If not set, TZ environment variable will be picked as default.

=item * B<to_level> => I<int>

Filter headlines having this level as the maximum.

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2012 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

