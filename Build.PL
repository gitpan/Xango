#!perl
# $Id: Build.PL 107 2006-05-17 09:01:19Z daisuke $
#
# Copyright (c) 2005 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

use strict;
use Module::Build;

my %requires = do 'tools/checkreqs.pl';
die if $@;

my $class = Module::Build->subclass(code => <<'EOSUB');
    sub ACTION_disttest
    {
        my $self = shift;
        local $ENV{PERL_TESTPOD} = 1;
        $self->SUPER::ACTION_disttest(@_);
    }

    sub find_test_files
    {
        my $self  = shift;
        my $tests = $self->SUPER::find_test_files(@_);

        return $tests if $ENV{PERL_TESTPOD};
        return [ grep { $_ !~ /\bpod.*\.t\z/ } @$tests ];
    }
EOSUB

my $build = $class->new(
    dist_name         => 'Xango',
    dist_version_from => 'lib/Xango.pm',
    module_author     => 'Daisuke Maki <dmaki@cpan.org>',
    license           => 'perl',
    requires          => \%requires,
    build_requires    => {
        'Test::More' => 0,
    },
    create_readme      => 1,
);

$build->create_build_script();