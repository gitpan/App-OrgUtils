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

our $VERSION = '0.21'; # VERSION

our %SPEC;

my $spec = clone($App::ListOrgHeadlines::SPEC{list_org_headlines});
$spec->{summary} = "List all todo items in all Org files";
delete $spec->{args}{todo};
$spec->{args}{done}{schema}[1]{default} = 0;
$spec->{args}{sort}{schema}[1]{default} = 'due_date';
$spec->{"x.dist.zilla.plugin.rinci.wrap.wrap_args"} = {validate_args=>0, validate_result=>0}; # don't bother checking arguments, they will be checked in list_org_headlines()

$SPEC{list_org_todos} = $spec;
 { my $meta = $App::ListOrgTodos::SPEC{list_org_todos}; $meta->{'x.perinci.sub.wrapper.log'} = [{'validate_args' => 0,'embed' => 1,'normalize_schema' => 1,'validate_result' => 0}]; $meta->{args}{'cache_dir'}{schema} = ['str',{'req' => 1},{}]; $meta->{args}{'detail'}{schema} = ['bool',{'default' => 0},{}]; $meta->{args}{'done'}{schema} = ['bool',{'default' => 0},{}]; $meta->{args}{'due_in'}{schema} = ['int',{},{}]; $meta->{args}{'files'}{schema} = ['array',{'min_len' => 1,'req' => 1,'of' => 'str*'},{}]; $meta->{args}{'from_level'}{schema} = ['int',{'default' => 1},{}]; $meta->{args}{'group_by_tags'}{schema} = ['bool',{'default' => 0},{}]; $meta->{args}{'has_tags'}{schema} = ['array',{},{}]; $meta->{args}{'lacks_tags'}{schema} = ['array',{},{}]; $meta->{args}{'priority'}{schema} = ['str',{},{}]; $meta->{args}{'sort'}{schema} = ['any',{'of' => [['str*',{'in' => ['due_date','-due_date']}],'code*'],'default' => 'due_date'},{}]; $meta->{args}{'state'}{schema} = ['str',{},{}]; $meta->{args}{'time_zone'}{schema} = ['str',{},{}]; $meta->{args}{'to_level'}{schema} = ['int',{},{}]; $meta->{args}{'today'}{schema} = ['any',{'of' => ['int',['obj',{'isa' => 'DateTime'}]]},{}]; } sub list_org_todos {
    my %args = @_;
 
    $args{done} //= 0;

    App::ListOrgHeadlines::list_org_headlines(%args, todo=>1);
}

1;
#ABSTRACT: List todo items in Org files

__END__

=pod

=encoding UTF-8

=head1 NAME

App::ListOrgTodos - List todo items in Org files

=head1 VERSION

version 0.21

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

List all todo items in all Org files.

=item * B<detail> => I<bool> (default: 0)

List all todo items in all Org files.

=item * B<done> => I<bool> (default: 0)

List all todo items in all Org files.

=item * B<due_in> => I<int>

List all todo items in all Org files.

=item * B<files>* => I<array>

List all todo items in all Org files.

=item * B<from_level> => I<int> (default: 1)

List all todo items in all Org files.

=item * B<group_by_tags> => I<bool> (default: 0)

List all todo items in all Org files.

=item * B<has_tags> => I<array>

List all todo items in all Org files.

=item * B<lacks_tags> => I<array>

List all todo items in all Org files.

=item * B<priority> => I<str>

List all todo items in all Org files.

=item * B<sort> => I<code|str> (default: "due_date")

List all todo items in all Org files.

=item * B<state> => I<str>

List all todo items in all Org files.

=item * B<time_zone> => I<str>

List all todo items in all Org files.

=item * B<to_level> => I<int>

List all todo items in all Org files.

=item * B<today> => I<int|obj>

List all todo items in all Org files.

=back

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

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

This software is copyright (c) 2014 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
