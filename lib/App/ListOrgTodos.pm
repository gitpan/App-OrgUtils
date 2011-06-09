package App::ListOrgTodos;
BEGIN {
  $App::ListOrgTodos::VERSION = '0.02';
}
#ABSTRACT: List todo items in Org files

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


=pod

=head1 NAME

App::ListOrgTodos - List todo items in Org files

=head1 VERSION

version 0.02

=head1 SYNOPSIS

 # See list-org-todos script

=head1 DESCRIPTION

=head1 FUNCTIONS

None are exported, but they are exportable.

=head1 AUTHOR

Steven Haryanto <stevenharyanto@gmail.com>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut


__END__

