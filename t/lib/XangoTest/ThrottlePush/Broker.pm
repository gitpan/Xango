#!perl
package XangoTest::ThrottlePush::Broker;
use strict;
use base qw(Xango::Broker::Push);
use POE;

sub _stop
{
    $_[OBJECT]->can('SUPER::_stop')->(@_);
}

1;
