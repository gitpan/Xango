# $Id: Util.pm 99 2006-03-04 01:30:59Z daisuke $
#
# Copyright (c) 2006 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package XangoTest::Util;
use strict;
use base qw(Exporter);
use vars qw(@EXPORT_OK);
@EXPORT_OK = qw(check_prereqs);

sub check_prereqs
{
    my $prereqs = shift || [ qw(
        POE::Component::Client::DNS
        POE::Component::Client::HTTP
        Cache::FileCache
    ) ];

    my $e;
    foreach my $module (@$prereqs) {
        eval "require $module";
        if ($@) {
            die "Prerequisite module $module not found: $@";
        }
    }
}

1;