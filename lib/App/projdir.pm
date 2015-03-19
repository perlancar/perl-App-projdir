package App::projdir;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

our %SPEC;

our %common_args = (
    short_dir => {
        schema => 'str*',
        cmdline_aliases => {s=>{}},
        req => 1,
    },
    long_dir => {
        schema => 'str*',
        cmdline_aliases => {l=>{}},
        req => 1,
    },
    long_include => {
        schema => ['array*', of=>'str*'],
    },
);

sub _preprocess_common_args {
    require File::HomeDir;

    my $args = shift;

    my $home = File::HomeDir->my_home;

    # replace tilde (~) with home dir
    for ($args->{short_dir}, $args->{long_dir}) {
        s/\A~/$home/;
    }
}

$SPEC{list_shorts} = {
    v => 1.1,
};
sub list_shorts {
    my %args = @_;
    _preprocess_common_args(\%args);

    my @res;
    opendir my($dh), $args->{short_dir} or
        return [500, "Can't open $args->{short_dir}: $!"];
    for my $ent (sort readdir($dh)) {
        next if $ent eq '.' || $ent eq '..';
        push @res, {
            name => $ent,

        };
    }
    [200, "OK", \@res];
}

1;
# ABSTRACT: Manage short project names

=head1 SYNOPSIS

Please see L<projdir> script.

=cut
