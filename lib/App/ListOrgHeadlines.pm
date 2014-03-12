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

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(list_org_headlines);

our $VERSION = '0.21'; # VERSION

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
            schema => ['array*' => of => 'str*', min_len=>1],
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
                of => ['int', [obj => {isa=>'DateTime'}]],
            }],
            summary => 'Assume today\'s date',
            description => <<'_',

You can provide Unix timestamp or DateTime object. If you provide a DateTime
object, remember to set the correct time zone.

_
        },
        sort => {
            schema => [any => {
                of => [
                    ['str*' => {in=>['due_date', '-due_date']}],
                    'code*',
                ],
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
{ my $meta = $App::ListOrgHeadlines::SPEC{list_org_headlines}; $meta->{'x.perinci.sub.wrapper.log'} = [{'validate_result' => 1,'normalize_schema' => 1,'embed' => 1,'validate_args' => 1}]; $meta->{args}{'cache_dir'}{schema} = ['str',{'req' => 1},{}]; $meta->{args}{'detail'}{schema} = ['bool',{'default' => 0},{}]; $meta->{args}{'done'}{schema} = ['bool',{},{}]; $meta->{args}{'due_in'}{schema} = ['int',{},{}]; $meta->{args}{'files'}{schema} = ['array',{'req' => 1,'of' => 'str*','min_len' => 1},{}]; $meta->{args}{'from_level'}{schema} = ['int',{'default' => 1},{}]; $meta->{args}{'group_by_tags'}{schema} = ['bool',{'default' => 0},{}]; $meta->{args}{'has_tags'}{schema} = ['array',{},{}]; $meta->{args}{'lacks_tags'}{schema} = ['array',{},{}]; $meta->{args}{'priority'}{schema} = ['str',{},{}]; $meta->{args}{'sort'}{schema} = ['any',{'of' => [['str*',{'in' => ['due_date','-due_date']}],'code*'],'default' => 'due_date'},{}]; $meta->{args}{'state'}{schema} = ['str',{},{}]; $meta->{args}{'time_zone'}{schema} = ['str',{},{}]; $meta->{args}{'to_level'}{schema} = ['int',{},{}]; $meta->{args}{'today'}{schema} = ['any',{'of' => ['int',['obj',{'isa' => 'DateTime'}]]},{}]; $meta->{args}{'todo'}{schema} = ['bool',{},{}]; } sub list_org_headlines {
    my %args = @_;
 my $_sahv_dpath = []; my $_w_res = undef; for (sort keys %args) { if (!/\A(-?)\w+(\.\w+)*\z/o) { return [400, "Invalid argument name '$_'"]; } if (!($1 || $_ ~~ ['cache_dir','detail','done','due_in','files','from_level','group_by_tags','has_tags','lacks_tags','priority','sort','state','time_zone','to_level','today','todo'])) { return [400, "Unknown argument '$_'"]; } } if (exists($args{'cache_dir'})) { my $err_cache_dir; ((defined($args{'cache_dir'})) ? 1 : (($err_cache_dir //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((!ref($args{'cache_dir'})) ? 1 : (($err_cache_dir //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0)); if ($err_cache_dir) { return [400, "Invalid value for argument 'cache_dir': $err_cache_dir"]; } } if (exists($args{'detail'})) { my $err_detail; ($args{'detail'} //= 0, 1) && (!defined($args{'detail'}) ? 1 :  ((!ref($args{'detail'})) ? 1 : (($err_detail //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type boolean value"),0))); if ($err_detail) { return [400, "Invalid value for argument 'detail': $err_detail"]; } } else { $args{'detail'} //= 0; } if (exists($args{'done'})) { my $err_done; (!defined($args{'done'}) ? 1 :  ((!ref($args{'done'})) ? 1 : (($err_done //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type boolean value"),0))); if ($err_done) { return [400, "Invalid value for argument 'done': $err_done"]; } } if (exists($args{'due_in'})) { my $err_due_in; (!defined($args{'due_in'}) ? 1 :  ((Scalar::Util::looks_like_number($args{'due_in'}) =~ /^(?:1|2|9|10|4352)$/) ? 1 : (($err_due_in //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type integer"),0))); if ($err_due_in) { return [400, "Invalid value for argument 'due_in': $err_due_in"]; } } if (exists($args{'files'})) { my $err_files; ((defined($args{'files'})) ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((ref($args{'files'}) eq 'ARRAY') ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type array"),0)) && ((@{$args{'files'}} >= 1) ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Length must be at least 1"),0)) && ((push(@$_sahv_dpath, undef), (!defined(List::Util::first(sub {!( ($_sahv_dpath->[-1] = defined($_sahv_dpath->[-1]) ? $_sahv_dpath->[-1]+1 : 0), ((defined($_)) ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((!ref($_)) ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0)) )}, @{$args{'files'}})))) ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text", pop(@$_sahv_dpath)),0)); if ($err_files) { return [400, "Invalid value for argument 'files': $err_files"]; } } if (!exists($args{'files'})) { return [400, "Missing required argument: files"]; } if (exists($args{'from_level'})) { my $err_from_level; ($args{'from_level'} //= 1, 1) && (!defined($args{'from_level'}) ? 1 :  ((Scalar::Util::looks_like_number($args{'from_level'}) =~ /^(?:1|2|9|10|4352)$/) ? 1 : (($err_from_level //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type integer"),0))); if ($err_from_level) { return [400, "Invalid value for argument 'from_level': $err_from_level"]; } } else { $args{'from_level'} //= 1; } if (exists($args{'group_by_tags'})) { my $err_group_by_tags; ($args{'group_by_tags'} //= 0, 1) && (!defined($args{'group_by_tags'}) ? 1 :  ((!ref($args{'group_by_tags'})) ? 1 : (($err_group_by_tags //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type boolean value"),0))); if ($err_group_by_tags) { return [400, "Invalid value for argument 'group_by_tags': $err_group_by_tags"]; } } else { $args{'group_by_tags'} //= 0; } if (exists($args{'has_tags'})) { my $err_has_tags; (!defined($args{'has_tags'}) ? 1 :  ((ref($args{'has_tags'}) eq 'ARRAY') ? 1 : (($err_has_tags //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type array"),0))); if ($err_has_tags) { return [400, "Invalid value for argument 'has_tags': $err_has_tags"]; } } if (exists($args{'lacks_tags'})) { my $err_lacks_tags; (!defined($args{'lacks_tags'}) ? 1 :  ((ref($args{'lacks_tags'}) eq 'ARRAY') ? 1 : (($err_lacks_tags //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type array"),0))); if ($err_lacks_tags) { return [400, "Invalid value for argument 'lacks_tags': $err_lacks_tags"]; } } if (exists($args{'priority'})) { my $err_priority; (!defined($args{'priority'}) ? 1 :  ((!ref($args{'priority'})) ? 1 : (($err_priority //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0))); if ($err_priority) { return [400, "Invalid value for argument 'priority': $err_priority"]; } } if (exists($args{'sort'})) { my $err_sort; ($args{'sort'} //= "due_date", 1) && (!defined($args{'sort'}) ? 1 :  ((1) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type any"),0)) && (((do { my $_sahv_ok = 0; my $_sahv_nok = 0; (                ((defined($args{'sort'})) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((!ref($args{'sort'})) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0)) && (($args{'sort'} ~~ ["due_date","-due_date"]) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Must be one of [\"due_date\",\"-due_date\"]"),0)) ? ++$_sahv_ok : ++$_sahv_nok) && (                ((defined($args{'sort'})) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((ref($args{'sort'}) eq 'CODE') ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type code"),0)) ? ++$_sahv_ok : ++$_sahv_nok) && $_sahv_ok >= 1 && ($err_sort = undef, 1)}) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input does not satisfy the following schema: must be one of the following: (text, must be one of [\"due_date\",\"-due_date\"]), code"),0)) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input does not satisfy the following schema: must be one of the following: (text, must be one of [\"due_date\",\"-due_date\"]), code"),0))); if ($err_sort) { return [400, "Invalid value for argument 'sort': $err_sort"]; } } else { $args{'sort'} //= 'due_date'; } if (exists($args{'state'})) { my $err_state; (!defined($args{'state'}) ? 1 :  ((!ref($args{'state'})) ? 1 : (($err_state //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0))); if ($err_state) { return [400, "Invalid value for argument 'state': $err_state"]; } } if (exists($args{'time_zone'})) { my $err_time_zone; (!defined($args{'time_zone'}) ? 1 :  ((!ref($args{'time_zone'})) ? 1 : (($err_time_zone //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0))); if ($err_time_zone) { return [400, "Invalid value for argument 'time_zone': $err_time_zone"]; } } if (exists($args{'to_level'})) { my $err_to_level; (!defined($args{'to_level'}) ? 1 :  ((Scalar::Util::looks_like_number($args{'to_level'}) =~ /^(?:1|2|9|10|4352)$/) ? 1 : (($err_to_level //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type integer"),0))); if ($err_to_level) { return [400, "Invalid value for argument 'to_level': $err_to_level"]; } } if (exists($args{'today'})) { my $err_today; (!defined($args{'today'}) ? 1 :  ((1) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type any"),0)) && (((do { my $_sahv_ok = 0; my $_sahv_nok = 0; (                (!defined($args{'today'}) ? 1 :  ((Scalar::Util::looks_like_number($args{'today'}) =~ /^(?:1|2|9|10|4352)$/) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type integer"),0))) ? ++$_sahv_ok : ++$_sahv_nok) && (                (!defined($args{'today'}) ? 1 :  ((Scalar::Util::blessed($args{'today'})) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type object"),0)) && (($args{'today'}->isa("DateTime")) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Must be subclass of DateTime"),0))) ? ++$_sahv_ok : ++$_sahv_nok) && $_sahv_ok >= 1 && ($err_today = undef, 1)}) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input does not satisfy the following schema: must be one of the following: integer, (object, must be subclass of DateTime)"),0)) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input does not satisfy the following schema: must be one of the following: integer, (object, must be subclass of DateTime)"),0))); if ($err_today) { return [400, "Invalid value for argument 'today': $err_today"]; } } if (exists($args{'todo'})) { my $err_todo; (!defined($args{'todo'}) ? 1 :  ((!ref($args{'todo'})) ? 1 : (($err_todo //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type boolean value"),0))); if ($err_todo) { return [400, "Invalid value for argument 'todo': $err_todo"]; } }    $_w_res = do {
    my $sort  = $args{sort};
    my $tz    = $args{time_zone} // $ENV{TZ} // "UTC";
    my $files = $args{files};
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
};      unless (ref($_w_res) eq "ARRAY" && $_w_res->[0]) { return [500, 'BUG: Sub App::ListOrgHeadlines::list_org_headlines does not produce envelope']; } return $_w_res; }

1;
#ABSTRACT: List headlines in Org files

__END__

=pod

=encoding UTF-8

=head1 NAME

App::ListOrgHeadlines - List headlines in Org files

=head1 VERSION

version 0.21

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

List all headlines in all Org files.

=item * B<detail> => I<bool> (default: 0)

List all headlines in all Org files.

=item * B<done> => I<bool>

List all headlines in all Org files.

=item * B<due_in> => I<int>

List all headlines in all Org files.

=item * B<files>* => I<array>

List all headlines in all Org files.

=item * B<from_level> => I<int> (default: 1)

List all headlines in all Org files.

=item * B<group_by_tags> => I<bool> (default: 0)

List all headlines in all Org files.

=item * B<has_tags> => I<array>

List all headlines in all Org files.

=item * B<lacks_tags> => I<array>

List all headlines in all Org files.

=item * B<priority> => I<str>

List all headlines in all Org files.

=item * B<sort> => I<code|str> (default: "due_date")

List all headlines in all Org files.

=item * B<state> => I<str>

List all headlines in all Org files.

=item * B<time_zone> => I<str>

List all headlines in all Org files.

=item * B<to_level> => I<int>

List all headlines in all Org files.

=item * B<today> => I<int|obj>

List all headlines in all Org files.

=item * B<todo> => I<bool>

List all headlines in all Org files.

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
