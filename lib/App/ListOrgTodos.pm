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

our $VERSION = '0.17'; # VERSION

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


=pod

=head1 NAME

App::ListOrgTodos - List todo items in Org files

=head1 VERSION

version 0.17

=head1 SYNOPSIS

 # See list-org-todos script

=head1 DESCRIPTION

=head1 FUNCTIONS

None are exported, but they are exportable.


=head2 list_org_todos() -> [status, msg, result, meta]

No arguments.

Return value:

Returns an enveloped result (an array). First element (status) is an integer containing HTTP status code (200 means OK, 4xx caller error, 5xx function error). Second element (msg) is a string containing error message, or 'OK' if status is 200. Third element (result) is optional, the actual result. Fourth element (meta) is called result metadata and is optional, a hash that contains extra information.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2013 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

