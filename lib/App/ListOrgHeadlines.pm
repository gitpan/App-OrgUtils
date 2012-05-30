package App::ListOrgHeadlines;

use 5.010;
use strict;
use warnings;
use Log::Any qw($log);

use DateTime;
use List::MoreUtils qw(uniq);
use Org::Parser;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(list_org_headlines);

our $VERSION = '0.12'; # VERSION

our %SPEC;

my $today;
my $yest;

sub _process_hl {
    my ($file, $hl, $args, $res, $opts) = @_;

    return if $args->{from_level} && $hl->level < $args->{from_level};
    return if $args->{to_level}   && $hl->level > $args->{to_level};
    if (defined $args->{todo}) {
        return if $args->{todo} xor $hl->is_todo;
    }
    if (defined $args->{done}) {
        return if $args->{done} xor $hl->is_done;
    }
    if (defined $args->{state}) {
        return unless $hl->is_todo &&
            $hl->todo_state eq $args->{state};
    }
    if ($args->{has_tags} || $args->{lacks_tags}) {
        my $tags = [$hl->get_tags];
        if ($args->{has_tags}) {
            for (@{ $args->{has_tags} }) {
                return unless $_ ~~ @$tags;
            }
        }
        if ($args->{lacks_tags}) {
            for (@{ $args->{lacks_tags} }) {
                return if $_ ~~ @$tags;
            }
        }
    }
    if (defined $args->{priority}) {
        my $p = $hl->todo_priority;
        return unless defined($p) && $args->{priority} eq $p;
    }

    my $ats = $hl->get_active_timestamp;
    my $days;
    $days = int(($ats->datetime->epoch - $today->epoch)/86400)
        if $ats;
    if (defined $args->{due_in}) {
        return unless $ats;
        my $met = $days <= $args->{due_in};
        if (!$met && $ats->_warning_period) {
            # try the warning period
            my $dt = $ats->datetime->clone;
            my $wp = $ats->_warning_period;
            $wp =~ s/(\w)$//;
            my $unit = $1;
            $wp = abs($wp);
            if ($unit eq 'd') {
                $dt->subtract(days => $wp);
            } elsif ($unit eq 'w') {
                $dt->subtract(weeks => $wp);
            } elsif ($unit eq 'm') {
                $dt->subtract(months => $wp);
            } elsif ($unit eq 'y') {
                $dt->subtract(years => $wp);
            } else {
                die "Can't understand unit '$unit' in timestamp's ".
                    "warning period: " . $ats->as_string;
                return;
            }
            $met++ if DateTime->compare($dt, $today) <= 0;
        }
        return unless $met;
    }

    my $r;
    my $date;
    if ($args->{detail}) {
        $r               = {};
        $r->{file}       = $file;
        $r->{title}      = $hl->title->as_string;
        $r->{due_date}   = $ats ? $ats->datetime : undef;
        $r->{priority}   = $hl->todo_priority;
        $r->{tags}       = [$hl->get_tags];
        $r->{is_todo}    = $hl->is_todo;
        $r->{is_done}    = $hl->is_done;
        $r->{todo_state} = $hl->todo_state;
        $r->{progress}   = $hl->progress;
        $r->{level}      = $hl->level;
        $date = $r->{due_date};
    } else {
        if ($ats) {
            my $pl = abs($days) > 1 ? "s" : "";
            $r = sprintf("%s: %s (%s)",
                         $days == 0 ? "today" :
                             $days < 0 ? abs($days)." day$pl ago" :
                                 "in $days day$pl",
                         $hl->title->as_string,
                         $ats->datetime->ymd);
            $date = $ats->datetime;
        } else {
            $r = $hl->title->as_string;
        }
    }
    push @$res, [$r, $date, $hl];
}

$SPEC{list_org_headlines} = {
    summary => 'List all headlines in all Org files',
    args    => {
        files => ['array*' => {
            of         => 'str*',
            arg_pos    => 0,
            arg_greedy => 1,
        }],
        todo => [bool => {
            summary => 'Filter headlines that are todos',
            default => 0,
        }],
        done => [bool => {
            summary => 'Filter todo items that are done',
        }],
        due_in => [int => {
            summary => 'Filter todo items which is due in this number of days',
            description => <<'_',

Note that if the todo's due date has warning period and the warning period is
active, then it will also pass this filter irregardless. Example, if today is
2011-06-30 and due_in is set to 7, then todo with due date <2011-07-10 > won't
pass the filter but <2011-07-10 Sun +1y -14d> will (warning period 14 days is
already active by that time).

_
        }],
        from_level => [int => {
            summary => 'Filter headlines having this level as the minimum',
            default => 1,
        }],
        to_level => [int => {
            summary => 'Filter headlines having this level as the maximum',
        }],
        state => [str => {
            summary => 'Filter todo items that have this state',
        }],
        detail => [bool => {
            summary => 'Show details instead of just titles',
            default => 0,
        }],
        has_tags => [array => {
            summary => 'Filter headlines that have the specified tags',
        }],
        lacks_tags => [array => {
            summary => 'Filter headlines that don\'t have the specified tags',
            arg_aliases => {
                lack_tags => {},
                'lack-tags' => {},
            },
        }],
        group_by_tags => [bool => {
            summary => 'Whether to group result by tags',
            default => 0,
            description => <<'_',

If set to true, instead of returning a list, this function will return a hash of
lists, keyed by tag: {tag1: [hl1, hl2, ...], tag2: [...]}. Note that some
headlines might be listed more than once if it has several tags.

_
        }],
        priority => [str => {
            summary => 'Filter todo items that have this priority',
        }],
        time_zone => [str => {
            summary => 'Will be passed to parser\'s options',
            description => <<'_',

If not set, TZ environment variable will be picked as default.

_
        }],
        sort => [any => {
            of => [
                ['str*' => {in=>['due_date', '-due_date']}],
                'code*'
            ],
            default => 'due_date',
            summary => 'Specify sorting',
            description => <<'_',

If string, must be one of 'due_date', '-due_date' (descending).

If code, sorting code will get [REC, DUE_DATE, HL] as the items to compare,
where REC is the final record that will be returned as final result (can be a
string or a hash, if 'detail' is enabled), DUE_DATE is the DateTime object (if
any), and HL is the Org::Headline object.

_
        }],
    },
};
sub list_org_headlines {
    my %args = @_;
    my $sort = $args{sort} // 'due_date';

    my $tz = $args{time_zone} // $ENV{TZ} // "UTC";

    my $files = $args{files};
    return [400, "Please specify files"] if !$files || !@$files;

    $today = DateTime->today(time_zone => $tz);
    $yest  = $today->clone->add(days => -1);

    my $orgp = Org::Parser->new;
    my @res;

    for my $file (@$files) {
        $log->debug("Parsing $file ...");
        my $opts = {time_zone => $tz};
        my $doc = $orgp->parse_file($file, $opts);
        $doc->walk(
            sub {
                my ($el) = @_;
                return unless $el->isa('Org::Element::Headline');
                _process_hl($file, $el, \%args, \@res, $opts)
            });
    } # for $file

    if ($sort) {
        if (ref($sort) eq 'CODE') {
            @res = sort $sort @res;
        } elsif ($sort =~ /^-?due_date$/) {
            @res = sort {
                my $dt1 = $a->[1];
                my $dt2 = $b->[1];
                my $comp;
                if ($dt1 && !$dt2) {
                    $comp = -1;
                } elsif (!$dt1 && $dt2) {
                    $comp = 1;
                } elsif (!$dt1 && !$dt2) {
                    $comp = 0;
                } else {
                    $comp = DateTime->compare($dt1, $dt2);
                }
                ($sort =~ /^-/ ? -1 : 1) * $comp;
            } @res;
        } else {
            # XXX should die here because when Sah is ready, invalid values have
            # been filtered
            return [400, "Invalid sort argument"];
        }
    }

    my $res;
    if ($args{group_by_tags}) {
        # cache tags in each @res element's [3] element
        for (@res) { $_->[3] = [$_->[2]->get_tags] }
        my @tags = sort uniq map {@{$_->[3]}} @res;
        $res = {};
        for my $tag ('', @tags) {
            $res->{$tag} = [];
            for (@res) {
                if ($tag eq '') {
                    next if @{$_->[3]};
                } else {
                    next unless $tag ~~ @{$_->[3]};
                }
                push @{ $res->{$tag} }, $_->[0];
            }
        }
    } else {
        $res = [map {$_->[0]} @res];
    }

    [200, "OK", $res];
}

1;
#ABSTRACT: List headlines in Org files


=pod

=head1 NAME

App::ListOrgHeadlines - List headlines in Org files

=head1 VERSION

version 0.12

=head1 SYNOPSIS

 # See list-org-headlines script

=head1 DESCRIPTION

=head1 FUNCTIONS

None are exported, but they are exportable.

=head1 FUNCTIONS


=head2 list_org_headlines(%args) -> [status, msg, result, meta]

List all headlines in all Org files.

Arguments ('*' denotes required arguments):

=over 4

=item * B<detail> => I<bool> (default: 0)

Show details instead of just titles.

=item * B<done> => I<bool>

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

=item * B<todo> => I<bool> (default: 0)

Filter headlines that are todos.

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

