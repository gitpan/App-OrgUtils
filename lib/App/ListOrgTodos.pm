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

our $VERSION = '0.07'; # VERSION

our %SPEC;

my $spec = clone($App::ListOrgHeadlines::SPEC{list_org_headlines});
$spec->{summary} = "List all todo items in all Org files";
delete $spec->{args}{todo};
#$spec->{args}{due_in}[1]{default} = 0;

$SPEC{list_org_todos} = $spec;
sub list_org_todos {
    my %args = @_;
    #$args{due_in} //= 0;

    App::ListOrgHeadlines::list_org_headlines(%args, todo=>1);
}

1;
#ABSTRACT: List todo items in Org files


=pod

=head1 NAME

App::ListOrgTodos - List todo items in Org files

=head1 VERSION

version 0.07

=head1 SYNOPSIS

 # See list-org-todos script

=head1 DESCRIPTION

=head1 FUNCTIONS

None are exported, but they are exportable.

=head2 list_org_todos(%args) -> [STATUS_CODE, ERR_MSG, RESULT]


List all todo items in all Org files.

Returns a 3-element arrayref. STATUS_CODE is 200 on success, or an error code
between 3xx-5xx (just like in HTTP). ERR_MSG is a string containing error
message, RESULT is the actual result.

Arguments (C<*> denotes required arguments):

=over 4

=item * B<files>* => I<array>

=item * B<detail> => I<bool> (default C<0>)

Show details instead of just titles.

=item * B<done> => I<bool>

Filter todo items that are done.

=item * B<due_in> => I<int>

Filter todo items which is due in this number of days.

Note that if the todo's due date has warning period and the warning period is
active, then it will also pass this filter irregardless. Example, if today is
2011-06-30 and due_in is set to 7, then todo with due date <2011-07-10 > won't
pass the filter but <2011-07-10 Sun +1y -14d> will (warning period 14 days is
already active by that time).

=item * B<from_level> => I<int> (default C<1>)

Filter headlines having this level as the minimum.

=item * B<has_tags> => I<array>

Filter headlines that have the specified tags.

=item * B<lack_tags> => I<array>

Filter headlines that don't have the specified tags.

=item * B<priority> => I<str>

Filter todo items that have this priority.

=item * B<state> => I<str>

Filter todo items that have this state.

=item * B<time_zone> => I<str>

Will be passed to parser's options.

If not set, TZ environment variable will be picked as default.

=item * B<to_level> => I<int>

Filter headlines having this level as the maximum.

=back

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

