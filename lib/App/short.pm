package App::short;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

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

sub _preprocess_common_args {
    my $args = shift;

    my $home = _get_my_home_dir() or die "Can't get homedir";

    # replace tilde (~) with home dir
    for ($args->{short_dir}, $args->{long_dir}) {
        s/\A~/$home/;
    }
}

$SPEC{list_shorts} = {
    v => 1.1,
    args => {
        %common_args,
        %detail_l_arg,
        broken => {
            schema => 'bool',
            tags => ['category:filtering'],
        },
    },
};
sub list_shorts {
    my %args = @_;
    _preprocess_common_args(\%args);

    my $S = $args{short_dir};

    my @res;
    opendir my($dh), $S or
        return [500, "Can't open dir $S: $!"];
    for my $ent (sort readdir($dh)) {
        next if $ent eq '.' || $ent eq '..';
        my $path = "$S/$ent";
        next unless -l $path;

        my $target = readlink($path);
        $target =~ s!.+[/\\]!!;

        my $broken = (-d $path) ? 0 : 1;

        # filter
        if (defined $args{broken}) {
            next if $args{broken} xor $broken;
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

1;
# ABSTRACT: Manage short directory symlinks

=head1 SYNOPSIS

Please see L<short> script.

=cut
