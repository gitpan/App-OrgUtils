package App::ListOrgHeadlines;

use 5.010001;
use strict;
use warnings;
use experimental 'smartmatch';
use Log::Any qw($log);

use App::OrgUtils;
use Cwd qw(abs_path);
use DateTime;
use Digest::MD5 qw(md5_hex);
use List::MoreUtils qw(uniq);
use Scalar::Util qw(reftype);

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(list_org_headlines);

our $VERSION = '0.20'; # VERSION

our %SPEC;

my $today;
my $yest;

sub _process_hl {
    my ($file, $hl, $args, $res) = @_;

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
    if (exists $args->{due_in}) {
        return unless $ats;
        my $met;
        if (defined $args->{due_in}) {
            $met = $days <= $args->{due_in};
        }
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
        if (!$met && !$ats->_warning_period && !defined($args->{due_in})) {
            # try the default 14 days
            $met = $days <= 14;
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
            $r = sprintf("%s (%s): %s (%s)",
                         $days == 0 ? "today" :
                             $days < 0 ? abs($days)." day$pl ago" :
                                 "in $days day$pl",
                         $ats->datetime->strftime("%a"),
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
    v       => 1.1,
    summary => 'List all headlines in all Org files',
    args    => {
        files => {
            schema => ['array*' => of => 'str*'],
            req    => 1,
            pos    => 0,
            greedy => 1,
        },
        cache_dir => {
            schema => ['str*'],
            summary => 'Cache Org parse result',
            description => <<'_',

Since Org::Parser can spend some time to parse largish Org files, this is an
option to store the parse result. Caching is turned on if this argument is set.

_
        },
        todo => {
            schema => ['bool'],
            summary => 'Only show headlines that are todos',
            tags => ['filter'],
        },
        done => {
            schema  => ['bool'],
            summary => 'Only show todo items that are done',
            tags => ['filter'],
        },
        due_in => {
            schema => ['int'],
            summary => 'Only show todo items that are (nearing|passed) due',
            description => <<'_',

If value is not set, then will use todo item's warning period (or, if todo item
does not have due date or warning period in its due date, will use the default
14 days).

If value is set to something smaller than the warning period, the todo item will
still be considered nearing due when the warning period is passed. For example,
if today is 2011-06-30 and due_in is set to 7, then todo item with due date
<2011-07-10 > won't pass the filter (it's still 10 days in the future, larger
than 7) but <2011-07-10 Sun +1y -14d> will (warning period 14 days is already
passed by that time).

_
            tags => ['filter'],
        },
        from_level => {
            schema => [int => default => 1],
            summary => 'Only show headlines having this level as the minimum',
            tags => ['filter'],
        },
        to_level => {
            schema => ['int'],
            summary => 'Only show headlines having this level as the maximum',
            tags => ['filter'],
        },
        state => {
            schema => ['str'],
            summary => 'Only show todo items that have this state',
            tags => ['filter'],
        },
        detail => {
            schema => [bool => default => 0],
            summary => 'Show details instead of just titles',
            tags => ['format'],
        },
        has_tags => {
            schema => ['array'],
            summary => 'Only show headlines that have the specified tags',
            tags => ['filter'],
        },
        lacks_tags => {
            schema => ['array'],
            summary=> 'Only show headlines that don\'t have the specified tags',
            tags => ['filter'],
        },
        group_by_tags => {
            schema => [bool => default => 0],
            summary => 'Whether to group result by tags',
            description => <<'_',

If set to true, instead of returning a list, this function will return a hash of
lists, keyed by tag: {tag1: [hl1, hl2, ...], tag2: [...]}. Note that some
headlines might be listed more than once if it has several tags.

_
            tags => ['format'],
        },
        priority => {
            schema => ['str'],
            summary => 'Only show todo items that have this priority',
            tags => ['filter'],
        },
        time_zone => {
            schema => ['str'],
            summary => 'Will be passed to parser\'s options',
            description => <<'_',

If not set, TZ environment variable will be picked as default.

_
        },
        today => {
            schema => ['any' => {
                # disable temporarily due to Data::Sah broken - 2012-12-25
                #of => ['int', [obj => {isa=>'DateTime'}]],
            }],
            summary => 'Assume today\'s date',
            description => <<'_',

You can provide Unix timestamp or DateTime object. If you provide a DateTime
object, remember to set the correct time zone.

_
        },
        sort => {
            schema => [any => {
                # disable temporarily due to Data::Sah broken - 2012-12-25
                #of => [
                #    ['str*' => {in=>['due_date', '-due_date']}],
                #    'code*'
                #],
                default => 'due_date',
            }],
            summary => 'Specify sorting',
            description => <<'_',

If string, must be one of 'due_date', '-due_date' (descending).

If code, sorting code will get [REC, DUE_DATE, HL] as the items to compare,
where REC is the final record that will be returned as final result (can be a
string or a hash, if 'detail' is enabled), DUE_DATE is the DateTime object (if
any), and HL is the Org::Headline object.

_
            tags => ['format'],
        },
    },
};
sub list_org_headlines {
    my %args = @_;
    my $sort = $args{sort} // 'due_date';

    my $tz = $args{time_zone} // $ENV{TZ} // "UTC";

    my $files = $args{files};
    return [400, "Please specify files"] if !$files || !@$files;

    if ($args{today}) {
        if (ref($args{today})) {
            $today = $args{today};
        } else {
            $today = DateTime->from_epoch(epoch=>$args{today}, time_zone=>$tz);
        }
    } else {
        $today = DateTime->today(time_zone => $tz);
    }
    $yest  = $today->clone->add(days => -1);

    my @res;

    my %docs = App::OrgUtils::_load_org_files_with_cache(
        $files, $args{cache_dir}, {time_zone=>$tz});
    for my $file (keys %docs) {
        my $doc = $docs{$file};
        $doc->walk(
            sub {
                my ($el) = @_;
                return unless $el->isa('Org::Element::Headline');
                _process_hl($file, $el, \%args, \@res)
            });
    }

    if ($sort) {
        if ((reftype($sort)//'') eq 'CODE') {
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
        my @tags = sort(uniq(map {@{$_->[3]}} @res));
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

    [200, "OK", $res, {result_format_options=>{
        "text"        => {list_max_columns=>1},
        "text-pretty" => {list_max_columns=>1},
    }}];
}

1;
#ABSTRACT: List headlines in Org files

__END__

=pod

=encoding UTF-8

=head1 NAME

App::ListOrgHeadlines - List headlines in Org files

=head1 VERSION

version 0.20

=head1 SYNOPSIS

 # See list-org-headlines script

=head1 DESCRIPTION

=head1 FUNCTIONS

None are exported, but they are exportable.


=head2 list_org_headlines(%args) -> [status, msg, result, meta]

List all headlines in all Org files.

Arguments ('*' denotes required arguments):

=over 4

=item * B<cache_dir> => I<str>

Cache Org parse result.

Since Org::Parser can spend some time to parse largish Org files, this is an
option to store the parse result. Caching is turned on if this argument is set.

=item * B<detail> => I<bool> (default: 0)

Show details instead of just titles.

=item * B<done> => I<bool>

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

=item * B<todo> => I<bool>

Only show headlines that are todos.

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

This software is copyright (c) 2013 by Steven Haryanto.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
