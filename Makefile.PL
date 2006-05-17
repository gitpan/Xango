# $Id: Makefile.PL 107 2006-05-17 09:01:19Z daisuke $
#
# Copyright (c) 2006 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

use strict;
use ExtUtils::MakeMaker;

my %requires = do 'tools/checkreqs.pl';

WriteMakefile(
    'DISTNAME'     => 'Xango',
    'VERSION_FROM' => 'lib/Xango.pm',
    'PREREQ_PM'    => \%requires,
    'INSTALLDIRS'  => 'site',
    'PL_FILES'     => {}
);
