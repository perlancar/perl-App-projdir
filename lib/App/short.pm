package App::short;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::Any::IfLOG '$log';

our %SPEC;

our %common_args = (
    short_dir => {
        schema => 'str*',
        cmdline_aliases => {S=>{}},
        req => 1,
    },
    long_dir => {
        schema => 'str*',
        cmdline_aliases => {L=>{}},
        req => 1,
    },
    long_include => {
        schema => ['array*', of=>'str*'],
    },
);

our %detail_l_arg = (
    detail => {
        schema => ['bool'],
        cmdline_aliases => {l=>{}},
    },
);

my $_completion_missing = sub {
    require Complete::Util;

    my %args = @_;
    my $word    = $args{word} // '';
    my $cmdline = $args{cmdline};
    my $r       = $args{r};

    return undef unless $cmdline;

    $r->{read_config} = 1;
    my $res = $cmdline->parse_argv($r);
    return undef unless $res->[0] == 200;

    my $fargs = $res->[2];

    $res = _validate($fargs);
    return undef unless $res->[0] == 200;

    $res = list_missing(_common_args($fargs));
    return undef unless $res->[0] == 200;

    Complete::Util::complete_array_elem(
        array=>$res->[2], word=>$word,
    );
};

my $_completion_short = sub {
    require Complete::Util;

    my %args = @_;
    my $word    = $args{word} // '';
    my $cmdline = $args{cmdline};
    my $r       = $args{r};

    return undef unless $cmdline;

    $r->{read_config} = 1;
    my $res = $cmdline->parse_argv($r);
    return undef unless $res->[0] == 200;

    my $fargs = $res->[2];

    $res = _validate($fargs);
    return undef unless $res->[0] == 200;

    $res = list_shorts(_common_args($fargs));
    return undef unless $res->[0] == 200;

    Complete::Util::complete_array_elem(
        array=>$res->[2], word=>$word,
    );
};

# (temporary) borrowed from PERLANCAR::Path::Util
sub _get_my_home_dir {
    if ($^O eq 'Win32') {
        # File::HomeDir always uses exists($ENV{x}) first, does it want to avoid
        # accidentally creating env vars?
        return $ENV{HOME} if $ENV{HOME};
        return $ENV{USERPROFILE} if $ENV{USERPROFILE};
        return join($ENV{HOMEDRIVE}, "\\", $ENV{HOMEPATH})
            if $ENV{HOMEDRIVE} && $ENV{HOMEPATH};
    } else {
        return $ENV{HOME} if $ENV{HOME};
        my @pw = getpwuid($>);
        return $pw[7] if @pw;
    }
    undef;
}

sub _common_args {
    my $args = shift;
    my %res;
    for (keys %common_args) {
        $res{$_} = $args->{$_} if exists $args->{$_};
    }
    %res;
}

sub _validate {
    my $args = shift;
    return [200] if $args->{-validated};

    my $home = _get_my_home_dir() or die "Can't get homedir";

    # replace tilde (~) with home dir
    for (qw/short_dir long_dir/) {
        if (defined $args->{$_}) {
            $args->{$_} =~ s/\A~/$home/;
        } else {
            return [400, "Please specify $_"];
        }
    }

    # convert to regex
    if ($args->{long_include}) {
        for (@{ $args->{long_include} }) {
            $_ = qr/$_/;
        }
    }

    my @caller = caller(1);
    my $func = $caller[3]; $func =~ s/.+:://;
    if (defined $args->{long}) {
        return [400, "Invalid long name"] if $args->{long} =~ m![/\\]!;
    }
    if (defined $args->{short}) {
        my @shorts = ref($args->{short}) eq 'ARRAY' ?
            @{$args->{short}} : ($args->{short});
        for (@shorts) {
            return [400, "Invalid short name '$_'"] if m![/\\]!;
        }
    }

    $args->{-validated}++;
    [200];
}

$SPEC{':package'} = {
    v => 1.1,
    summary => 'Manage short directory symlinks',
};

$SPEC{list_shorts} = {
    v => 1.1,
    args => {
        %common_args,
        %detail_l_arg,
        broken => {
            schema => 'bool',
            tags => ['category:filtering'],
        },
        query => {
            schema => 'str*',
            tags => ['category:filtering'],
            pos => 0,
        },
    },
};
sub list_shorts {
    my %args = @_;
    my $res = _validate(\%args);
    return $res unless $res->[0] == 200;

    my $S = $args{short_dir};

    my $q = lc($args{query} // '');

    my @res;
    opendir my($dh), $S or
        return [500, "Can't open dir $S: $!"];
    for my $ent (sort readdir($dh)) {
        next if $ent eq '.' || $ent eq '..';
        my $path = "$S/$ent";
        next unless -l $path;

        my $target = readlink($path);
        $target =~ s!.+[/\\]!!;

        # XXX check that target refers to $L

        my $broken = (-d $path) ? 0 : 1;

        # filter
        if (defined $args{broken}) {
            next if $args{broken} xor $broken;
        }
        if (length($q)) {
            next unless index(lc($target), $q) >= 0 || index(lc($ent), $q) >= 0;
        }

        push @res, {
            name => $ent,
            is_broken => $broken,
            target => $target,
        };
    }

    my %resmeta;
    if ($args{detail}) {
        $resmeta{format_options} = {
            any => {table_column_orders=>[[qw/name target is_broken/]]},
        };
    } else {
        @res = map {$_->{name}} @res;
    }

    [200, "OK", \@res, \%resmeta];
}

$SPEC{list_longs} = {
    v => 1.1,
    args => {
        %common_args,
        %detail_l_arg,
    },
};
sub list_longs {
    my %args = @_;
    my $res = _validate(\%args);
    return $res unless $res->[0] == 200;

    my $L = $args{long_dir};

    my @res;
    opendir my($dh), $L or
        return [500, "Can't open dir $L: $!"];
  ENTRY:
    for my $ent (sort readdir($dh)) {
        next if $ent eq '.' || $ent eq '..';
        my $path = "$L/$ent";
        next unless -d $path;

      FILTER_INCLUDE:
        {
            if ($args{long_include}) {
                for (@{ $args{long_include} }) {
                    last FILTER_INCLUDE if $ent =~ $_;
                }
                next ENTRY;
            }
        }

        push @res, {
            name => $ent,
        };
    }

    my %resmeta;
    if ($args{detail}) {
        $resmeta{format_options} = {
            any => {table_column_orders=>[[qw/name/]]},
        };
    } else {
        @res = map {$_->{name}} @res;
    }

    [200, "OK", \@res, \%resmeta];
}

$SPEC{list_missing} = {
    v => 1.1,
    args => {
        %common_args,
        %detail_l_arg,
    },
};
sub list_missing {
    use experimental 'smartmatch';

    my %args = @_;
    my $res = _validate(\%args);
    return $res unless $res->[0] == 200;

    my $S = $args{short_dir};
    my $L = $args{long_dir};

    my $res_s = list_shorts(_common_args(\%args), broken=>0, detail=>1);
    my $res_l = list_longs(_common_args(\%args));

    my @mentioned_longs = map {$_->{target}} @{$res_s->[2]};

    my @res;
    for (@{ $res_l->[2] }) {
        next if $_ ~~ @mentioned_longs;
        push @res, {
            name => $_,
        };
    }

    my %resmeta;
    if ($args{detail}) {
        $resmeta{format_options} = {
            any => {table_column_orders=>[[qw/name/]]},
        };
    } else {
        @res = map {$_->{name}} @res;
    }

    [200, "OK", \@res];
}

$SPEC{get_short_target} = {
    v => 1.1,
    args => {
        %common_args,
        short => {
            schema => 'str*',
            req => 1,
            pos => 0,
            completion => $_completion_short,
        },
    },
};
sub get_short_target {
    require Cwd;
    require File::Spec;

    my %args = @_;
    my $res = _validate(\%args);
    return [200,"Invalid input: $res->[0] - $res->[1]"]
        unless $res->[0] == 200;

    my $S = $args{short_dir};
    #my $L = $args{long_dir};

    my $dir = readlink("$S/$args{short}");
    return [200, "Short name not found"] unless $dir;
    $dir = Cwd::abs_path(
        File::Spec->rel2abs(
            $dir, Cwd::abs_path($S),
        ));
    return [200, "Can't abs_path"] unless $dir;
    [200, "OK", $dir];
}

$SPEC{add_short} = {
    v => 1.1,
    args => {
        %common_args,
        long => {
            schema => 'str*',
            req => 1,
            pos => 0,
            completion => $_completion_missing,
        },
        short => {
            schema => 'str*',
            req => 1,
            pos => 1,
        },
    },
};
sub add_short {
    use experimental 'smartmatch';
    require Cwd;
    require File::Spec;

    my %args = @_;
    my $res = _validate(\%args);
    return $res unless $res->[0] == 200;

    my $S = $args{short_dir};
    my $L = $args{long_dir};

    return [404, "No such long name '$args{long}'"]
        unless (-d "$L/$args{long}");
    return [412, "Short name '$args{short}' already exists"]
        if (-l "$S/$args{short}");

    symlink(File::Spec->abs2rel(
        Cwd::abs_path("$L/$args{long}"),
        Cwd::abs_path($S),
    ), "$S/$args{short}") or return [500, "Can't create symlink: $!"];

    [200, "OK"];
}

$SPEC{rm_short} = {
    v => 1.1,
    args => {
        %common_args,
        short => {
            schema => ['array*', of=>'str*', min_len=>1],
            req => 1,
            pos => 0,
            greedy => 1,
            element_completion => $_completion_short,
        },
    },
};
sub rm_short {
    require Perinci::Object;

    my %args = @_;
    my $res = _validate(\%args);
    return $res unless $res->[0] == 200;

    my $S = $args{short_dir};

    my $envres = Perinci::Object::envresmulti();

    for my $s (@{ $args{short} }) {
        my $path = "$S/$s";

        if (!(-l $path)) {
            $envres->add_result(404, "Short name not found", {item_id=>$s});
        } elsif (!unlink($path)) {
            $envres->add_result(500, "Can't unlink: $!", {item_id=>$s});
        } else {
            $envres->add_result(200, "OK", {item_id=>$s});
        }
    }

    $envres->as_struct;
}

1;
# ABSTRACT:

=head1 SYNOPSIS

Please see L<short> script.

=cut
