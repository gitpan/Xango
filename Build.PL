#!perl
# $Id: Build.PL 79 2005-10-13 03:54:54Z daisuke $
#
# Copyright (c) 2005 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

use strict;
use Module::Build;

my %requires = (
    'Log::Dispatch' => 0,
    'POE'           => 0,
    'YAML'          => 0, # See Xango::Config
);

my @ask;
my @optional = (
    qw(POE::Component::Client::DNS POE::Component::Client::HTTP),
    qw(Cache::FileCache)
);
foreach my $module(@optional) {
    my $r = Module::Build->check_installed_status($module, 0);
    next if $r->{ok};

    print "* $module not installed\n";
    push @ask, $module;
}

if (@ask) {
    print <<EOM;

Xango by default uses the following missing modules. If you know what you
are doing (and/or plan to customize the modules that are going to be used),
then you do not need to install them.

EOM
    foreach my $module (@ask) {
        my $require_mod = Module::Build->y_n("Install $module?", 'y');
        if ($require_mod) {
            $requires{$module} = 0;
        }
    }
}

my $class = 'Module::Build';
my $build = $class->new(
    module_name   => 'Xango',
    module_author => 'Daisuke Maki <dmaki@cpan.org>',
    license       => 'perl',
    requires      => \%requires,
    build_requires     => {
        'Test::More' => 0,
    },
    create_makefile_pl => 'traditional',
    create_readme      => 1,
);

$build->create_build_script();