package App::ListOrgAnniversaries;

use 5.010;
use strict;
use warnings;
use experimental 'smartmatch';
use Log::Any qw($log);

use App::OrgUtils;
use Cwd qw(abs_path);
use DateTime;
use Digest::MD5 qw(md5_hex);
use Lingua::EN::Numbers::Ordinate;

require Exporter;
our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(list_org_anniversaries);

our $VERSION = '0.21'; # VERSION

our %SPEC;

my $today;
my $yest;

sub _process_hl {
    my ($file, $hl, $args, $res, $tz) = @_;

    return unless $hl->is_leaf;

    $log->tracef("Processing %s ...", $hl->title->as_string);

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

    my @annivs;
    $hl->walk(
        sub {
            my ($el) = @_;

            if ($el->isa('Org::Element::Timestamp')) {
                my $field = $el->field_name;
                return unless defined($field) &&
                    $field =~ $args->{field_pattern};
                push @annivs, [$field, $el->datetime];
                return;
            }
            if ($el->isa('Org::Element::Drawer') && $el->name eq 'PROPERTIES') {
                my $props = $el->properties;
                for my $k (keys %$props) {
                    next unless $k =~ $args->{field_pattern};
                    my $v = $props->{$k};
                    unless ($v =~ /^\s*(\d{4})-(\d{2})-(\d{2})\s*$/) {
                        $log->warn("Invalid date format $v, ".
                                       "must be YYYY-MM-DD");
                        next;
                    }
                    push @annivs,
                        [$k, DateTime->new(year=>$1, month=>$2, day=>$3,
                                       time_zone=>$tz)];
                    return;
                }
            }
        }
    );

    if (!@annivs) {
        $log->debug("Node doesn't contain anniversary fields, skipped");
        return;
    }
    $log->tracef("annivs = ", \@annivs);
    for my $anniv (@annivs) {
        my ($field, $date) = @$anniv;
        $log->debugf("Anniversary found: field=%s, date=%s",
                     $field, $date->ymd);
        my $y = $today->year - $date->year;
        my $date_ly = $date->clone; $date_ly->add(years => $y-1);
        my $date_ty = $date->clone; $date_ty->add(years => $y  );
        my $date_ny = $date->clone; $date_ny->add(years => $y+1);
      DATE:
        for my $d ($date_ly, $date_ty, $date_ny) {
            my $days = int(($d->epoch - $today->epoch)/86400);
            next if defined($args->{due_in}) &&
                $days > $args->{due_in};
            next if defined($args->{max_overdue}) &&
                -$days > $args->{max_overdue};
            next if !defined($args->{due_in}) &&
                !defined($args->{max_overdue}) &&
                    DateTime->compare($d, $today) < 0;
            my $pl = abs($days) > 1 ? "s" : "";
            my $hide_age = $date->year == 1900;
            my $msg = sprintf(
                "%s (%s): %s of %s (%s)",
                $days == 0 ? "today" :
                    $days < 0 ? abs($days)." day$pl ago" :
                        "in $days day$pl",
                $d->strftime("%a"),
                $hide_age ? $field :
                    ordinate($d->year - $date->year)." $field",
                $hl->title->as_string,
                $hide_age ? $d->ymd : $date->ymd . " - " . $d->ymd);
            $log->debugf("Added this anniversary to result: %s", $msg);
            push @$res, [$msg, $d];
            last DATE;
        }
    } # for @annivs
}

$SPEC{list_org_anniversaries} = {
    v => 1.1,
    summary => 'List all anniversaries in Org files',
    description => <<'_',
This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('has_tags' and 'lacks_tags' options), or by 'due_in' and
'max_overdue' options (due_in=14 and max_overdue=2 is what I commonly use in my
startup script).

_
    args    => {
        files => {
            schema  => ['array*' => {of => 'str*', min_len=>1}],
            req     => 1,
            pos     => 0,
            greedy  => 1,
        },
        cache_dir => {
            summary => 'Cache Org parse result',
            schema  => ['str*'],
            description => <<'_',

Since Org::Parser can spend some time to parse largish Org files, this is an
option to store the parse result. Caching is turned on if this argument is set.

_
        },
        field_pattern => {
            summary => 'Field regex that specifies anniversaries',
            schema  => [str => {
                default => '(?:birthday|anniversary)',
            }],
        },
        has_tags => {
            summary => 'Filter headlines that have the specified tags',
            schema  => [array => {of => 'str*'}],
        },
        lacks_tags => {
            summary => 'Filter headlines that don\'t have the specified tags',
            schema  => [array => {of => 'str*'}],
        },
        due_in => {
            summary => 'Only show anniversaries that are due '.
                'in this number of days',
            schema  => ['int'],
        },
        max_overdue => {
            summary => 'Don\'t show dates that are overdue '.
                'more than this number of days',
            schema  => ['int'],
        },
        time_zone => {
            summary => 'Will be passed to parser\'s options',
            schema  => ['str'],
            description => <<'_',

If not set, TZ environment variable will be picked as default.

_
        },
        today => {
            summary => 'Assume today\'s date',
            schema  => [any => {
                of => ['int', [obj => {isa=>'DateTime'}]],
            }],
            description => <<'_',

You can provide Unix timestamp or DateTime object. If you provide a DateTime
object, remember to set the correct time zone.

_
        },
        sort => {
            summary => 'Specify sorting',
            schema  => [any => {
                of => [
                    ['str*' => {in=>['due_date', '-due_date']}],
                    'code*',
                ],
                default => 'due_date',
            }],
            description => <<'_',

If string, must be one of 'date', '-date' (descending).

If code, sorting code will get [REC, DUE_DATE] as the items to compare, where
REC is the final record that will be returned as final result (can be a string
or a hash, if 'detail' is enabled), and DUE_DATE is the DateTime object.

_
        },
    },
};
{ my $meta = $App::ListOrgAnniversaries::SPEC{list_org_anniversaries}; $meta->{'x.perinci.sub.wrapper.log'} = [{'validate_args' => 1,'embed' => 1,'normalize_schema' => 1,'validate_result' => 1}]; $meta->{args}{'cache_dir'}{schema} = ['str',{'req' => 1},{}]; $meta->{args}{'due_in'}{schema} = ['int',{},{}]; $meta->{args}{'field_pattern'}{schema} = ['str',{'default' => '(?:birthday|anniversary)'},{}]; $meta->{args}{'files'}{schema} = ['array',{'req' => 1,'of' => 'str*','min_len' => 1},{}]; $meta->{args}{'has_tags'}{schema} = ['array',{'of' => 'str*'},{}]; $meta->{args}{'lacks_tags'}{schema} = ['array',{'of' => 'str*'},{}]; $meta->{args}{'max_overdue'}{schema} = ['int',{},{}]; $meta->{args}{'sort'}{schema} = ['any',{'of' => [['str*',{'in' => ['due_date','-due_date']}],'code*'],'default' => 'due_date'},{}]; $meta->{args}{'time_zone'}{schema} = ['str',{},{}]; $meta->{args}{'today'}{schema} = ['any',{'of' => ['int',['obj',{'isa' => 'DateTime'}]]},{}]; } sub list_org_anniversaries {
    my %args = @_;
 my $_sahv_dpath = []; my $_w_res = undef; for (sort keys %args) { if (!/\A(-?)\w+(\.\w+)*\z/o) { return [400, "Invalid argument name '$_'"]; } if (!($1 || $_ ~~ ['cache_dir','due_in','field_pattern','files','has_tags','lacks_tags','max_overdue','sort','time_zone','today'])) { return [400, "Unknown argument '$_'"]; } } if (exists($args{'cache_dir'})) { my $err_cache_dir; ((defined($args{'cache_dir'})) ? 1 : (($err_cache_dir //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((!ref($args{'cache_dir'})) ? 1 : (($err_cache_dir //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0)); if ($err_cache_dir) { return [400, "Invalid value for argument 'cache_dir': $err_cache_dir"]; } } if (exists($args{'due_in'})) { my $err_due_in; (!defined($args{'due_in'}) ? 1 :  ((Scalar::Util::looks_like_number($args{'due_in'}) =~ /^(?:1|2|9|10|4352)$/) ? 1 : (($err_due_in //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type integer"),0))); if ($err_due_in) { return [400, "Invalid value for argument 'due_in': $err_due_in"]; } } if (exists($args{'field_pattern'})) { my $err_field_pattern; ($args{'field_pattern'} //= "(?:birthday|anniversary)", 1) && (!defined($args{'field_pattern'}) ? 1 :  ((!ref($args{'field_pattern'})) ? 1 : (($err_field_pattern //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0))); if ($err_field_pattern) { return [400, "Invalid value for argument 'field_pattern': $err_field_pattern"]; } } else { $args{'field_pattern'} //= '(?:birthday|anniversary)'; } if (exists($args{'files'})) { my $err_files; ((defined($args{'files'})) ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((ref($args{'files'}) eq 'ARRAY') ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type array"),0)) && ((@{$args{'files'}} >= 1) ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Length must be at least 1"),0)) && ((push(@$_sahv_dpath, undef), (!defined(List::Util::first(sub {!( ($_sahv_dpath->[-1] = defined($_sahv_dpath->[-1]) ? $_sahv_dpath->[-1]+1 : 0), ((defined($_)) ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((!ref($_)) ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0)) )}, @{$args{'files'}})))) ? 1 : (($err_files //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text", pop(@$_sahv_dpath)),0)); if ($err_files) { return [400, "Invalid value for argument 'files': $err_files"]; } } if (!exists($args{'files'})) { return [400, "Missing required argument: files"]; } if (exists($args{'has_tags'})) { my $err_has_tags; (!defined($args{'has_tags'}) ? 1 :  ((ref($args{'has_tags'}) eq 'ARRAY') ? 1 : (($err_has_tags //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type array"),0)) && ((push(@$_sahv_dpath, undef), (!defined(List::Util::first(sub {!( ($_sahv_dpath->[-1] = defined($_sahv_dpath->[-1]) ? $_sahv_dpath->[-1]+1 : 0), ((defined($_)) ? 1 : (($err_has_tags //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((!ref($_)) ? 1 : (($err_has_tags //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0)) )}, @{$args{'has_tags'}})))) ? 1 : (($err_has_tags //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text", pop(@$_sahv_dpath)),0))); if ($err_has_tags) { return [400, "Invalid value for argument 'has_tags': $err_has_tags"]; } } if (exists($args{'lacks_tags'})) { my $err_lacks_tags; (!defined($args{'lacks_tags'}) ? 1 :  ((ref($args{'lacks_tags'}) eq 'ARRAY') ? 1 : (($err_lacks_tags //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type array"),0)) && ((push(@$_sahv_dpath, undef), (!defined(List::Util::first(sub {!( ($_sahv_dpath->[-1] = defined($_sahv_dpath->[-1]) ? $_sahv_dpath->[-1]+1 : 0), ((defined($_)) ? 1 : (($err_lacks_tags //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((!ref($_)) ? 1 : (($err_lacks_tags //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0)) )}, @{$args{'lacks_tags'}})))) ? 1 : (($err_lacks_tags //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text", pop(@$_sahv_dpath)),0))); if ($err_lacks_tags) { return [400, "Invalid value for argument 'lacks_tags': $err_lacks_tags"]; } } if (exists($args{'max_overdue'})) { my $err_max_overdue; (!defined($args{'max_overdue'}) ? 1 :  ((Scalar::Util::looks_like_number($args{'max_overdue'}) =~ /^(?:1|2|9|10|4352)$/) ? 1 : (($err_max_overdue //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type integer"),0))); if ($err_max_overdue) { return [400, "Invalid value for argument 'max_overdue': $err_max_overdue"]; } } if (exists($args{'sort'})) { my $err_sort; ($args{'sort'} //= "due_date", 1) && (!defined($args{'sort'}) ? 1 :  ((1) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type any"),0)) && (((do { my $_sahv_ok = 0; my $_sahv_nok = 0; (                ((defined($args{'sort'})) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((!ref($args{'sort'})) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0)) && (($args{'sort'} ~~ ["due_date","-due_date"]) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Must be one of [\"due_date\",\"-due_date\"]"),0)) ? ++$_sahv_ok : ++$_sahv_nok) && (                ((defined($args{'sort'})) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Required input not specified"),0)) && ((ref($args{'sort'}) eq 'CODE') ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type code"),0)) ? ++$_sahv_ok : ++$_sahv_nok) && $_sahv_ok >= 1 && ($err_sort = undef, 1)}) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input does not satisfy the following schema: must be one of the following: (text, must be one of [\"due_date\",\"-due_date\"]), code"),0)) ? 1 : (($err_sort //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input does not satisfy the following schema: must be one of the following: (text, must be one of [\"due_date\",\"-due_date\"]), code"),0))); if ($err_sort) { return [400, "Invalid value for argument 'sort': $err_sort"]; } } else { $args{'sort'} //= 'due_date'; } if (exists($args{'time_zone'})) { my $err_time_zone; (!defined($args{'time_zone'}) ? 1 :  ((!ref($args{'time_zone'})) ? 1 : (($err_time_zone //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type text"),0))); if ($err_time_zone) { return [400, "Invalid value for argument 'time_zone': $err_time_zone"]; } } if (exists($args{'today'})) { my $err_today; (!defined($args{'today'}) ? 1 :  ((1) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type any"),0)) && (((do { my $_sahv_ok = 0; my $_sahv_nok = 0; (                (!defined($args{'today'}) ? 1 :  ((Scalar::Util::looks_like_number($args{'today'}) =~ /^(?:1|2|9|10|4352)$/) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type integer"),0))) ? ++$_sahv_ok : ++$_sahv_nok) && (                (!defined($args{'today'}) ? 1 :  ((Scalar::Util::blessed($args{'today'})) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input is not of type object"),0)) && (($args{'today'}->isa("DateTime")) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Must be subclass of DateTime"),0))) ? ++$_sahv_ok : ++$_sahv_nok) && $_sahv_ok >= 1 && ($err_today = undef, 1)}) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input does not satisfy the following schema: must be one of the following: integer, (object, must be subclass of DateTime)"),0)) ? 1 : (($err_today //= (@$_sahv_dpath ? '@'.join("/",@$_sahv_dpath).": " : "") . "Input does not satisfy the following schema: must be one of the following: integer, (object, must be subclass of DateTime)"),0))); if ($err_today) { return [400, "Invalid value for argument 'today': $err_today"]; } }    $_w_res = do {
    my $sort  = $args{sort};
    my $tz    = $args{time_zone} // $ENV{TZ} // "UTC";
    my $files = $args{files};
    my $f     = $args{field_pattern};
    return [400, "Invalid field_pattern: $@"] unless eval { $f = qr/$f/i };
    $args{field_pattern} = $f;
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

    my $orgp = Org::Parser->new;
    my @res;

    my %docs = App::OrgUtils::_load_org_files_with_cache(
        $files, $args{cache_dir}, {time_zone=>$tz});
    for my $file (keys %docs) {
        my $doc = $docs{$file};
        $doc->walk(
            sub {
                my ($el) = @_;
                return unless $el->isa('Org::Element::Headline');
                _process_hl($file, $el, \%args, \@res, $tz);
            });
    }

    if ($sort) {
        if (ref($sort) eq 'CODE') {
            @res = sort $sort @res;
        } elsif ($sort =~ /^-?due_date$/) {
            @res = sort {
                my $dt1 = $a->[1];
                my $dt2 = $b->[1];
                my $comp = DateTime->compare($dt1, $dt2);
                ($sort =~ /^-/ ? -1 : 1) * $comp;
            } @res;
        }
    }

    [200, "OK", [map {$_->[0]} @res],
     {result_format_opts=>{list_max_columns=>1}}];
};      unless (ref($_w_res) eq "ARRAY" && $_w_res->[0]) { return [500, 'BUG: Sub App::ListOrgAnniversaries::list_org_anniversaries does not produce envelope']; } return $_w_res; }

1;
#ABSTRACT: List headlines in Org files

__END__

=pod

=encoding UTF-8

=head1 NAME

App::ListOrgAnniversaries - List headlines in Org files

=head1 VERSION

version 0.21

=head1 SYNOPSIS

 # See list-org-anniversaries script

=head1 DESCRIPTION

This module uses L<Log::Any> logging framework.

=head1 FUNCTIONS

None are exported, but they are exportable.


=head2 list_org_anniversaries(%args) -> [status, msg, result, meta]

List all anniversaries in Org files.

This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('hasI<tags' and 'lacks>tags' options), or by 'dueI<in' and
'max>overdue' options (dueI<in=14 and max>overdue=2 is what I commonly use in my
startup script).

Arguments ('*' denotes required arguments):

=over 4

=item * B<cache_dir> => I<str>

List all anniversaries in Org files.

This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('hasI<tags' and 'lacks>tags' options), or by 'dueI<in' and
'max>overdue' options (dueI<in=14 and max>overdue=2 is what I commonly use in my
startup script).

=item * B<due_in> => I<int>

List all anniversaries in Org files.

This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('hasI<tags' and 'lacks>tags' options), or by 'dueI<in' and
'max>overdue' options (dueI<in=14 and max>overdue=2 is what I commonly use in my
startup script).

=item * B<field_pattern> => I<str> (default: "(?:birthday|anniversary)")

List all anniversaries in Org files.

This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('hasI<tags' and 'lacks>tags' options), or by 'dueI<in' and
'max>overdue' options (dueI<in=14 and max>overdue=2 is what I commonly use in my
startup script).

=item * B<files>* => I<array>

List all anniversaries in Org files.

This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('hasI<tags' and 'lacks>tags' options), or by 'dueI<in' and
'max>overdue' options (dueI<in=14 and max>overdue=2 is what I commonly use in my
startup script).

=item * B<has_tags> => I<array>

List all anniversaries in Org files.

This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('hasI<tags' and 'lacks>tags' options), or by 'dueI<in' and
'max>overdue' options (dueI<in=14 and max>overdue=2 is what I commonly use in my
startup script).

=item * B<lacks_tags> => I<array>

List all anniversaries in Org files.

This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('hasI<tags' and 'lacks>tags' options), or by 'dueI<in' and
'max>overdue' options (dueI<in=14 and max>overdue=2 is what I commonly use in my
startup script).

=item * B<max_overdue> => I<int>

List all anniversaries in Org files.

This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('hasI<tags' and 'lacks>tags' options), or by 'dueI<in' and
'max>overdue' options (dueI<in=14 and max>overdue=2 is what I commonly use in my
startup script).

=item * B<sort> => I<code|str> (default: "due_date")

List all anniversaries in Org files.

This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('hasI<tags' and 'lacks>tags' options), or by 'dueI<in' and
'max>overdue' options (dueI<in=14 and max>overdue=2 is what I commonly use in my
startup script).

=item * B<time_zone> => I<str>

List all anniversaries in Org files.

This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('hasI<tags' and 'lacks>tags' options), or by 'dueI<in' and
'max>overdue' options (dueI<in=14 and max>overdue=2 is what I commonly use in my
startup script).

=item * B<today> => I<int|obj>

List all anniversaries in Org files.

This function expects contacts in the following format:

    * First last                              :office:friend:
      :PROPERTIES:
      :BIRTHDAY:     1900-06-07
      :EMAIL:        foo@example.com
      :OTHERFIELD:   ...
      :END:

or:

    * Some name                               :office:
      - birthday   :: [1900-06-07 ]
      - email      :: foo@example.com
      - otherfield :: ...

Using PROPERTIES, dates currently must be specified in "YYYY-MM-DD" format.
Other format will be supported in the future. Using description list, dates can
be specified using normal Org timestamps (repeaters and warning periods will be
ignored).

By convention, if year is '1900' it is assumed to mean year is not specified.

By default, all contacts' anniversaries will be listed. You can filter contacts
using tags ('hasI<tags' and 'lacks>tags' options), or by 'dueI<in' and
'max>overdue' options (dueI<in=14 and max>overdue=2 is what I commonly use in my
startup script).

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
