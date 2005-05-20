#!perl
# $Id: Build.PL 60 2005-05-20 06:41:18Z daisuke $
#
# Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

use strict;
use Module::Build;

my %requires = (
    'Log::Dispatch'                    => 0,
    'POE'                              => 0,
    'YAML'                             => 0, # See Xango::Config
);

my @optional = qw(POE::Component::Client::DNS POE::Component::Client::HTTP);
foreach my $module(@optional) {
    my $r = Module::Build->check_installed_status($module, 0);
    if (! $r->{ok}) {
        my $require_mod = Module::Build->y_n(<<EOM, 'y');
***********************
$module not installed. This module does not require $module if you plan to implement your own module to handle the task.

Would you like to install the module $module ?
EOM
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
    sign          => 1,
    requires      => \%requires,
    build_requires     => {
        'Test::More' => 0,
    },
    create_makefile_pl => 'traditional',
);

$build->create_build_script();