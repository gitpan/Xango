#!perl
use strict;
use Test::More (tests => 3);

BEGIN
{
    use_ok("Xango");
    use_ok("Xango::Broker::Pull");
    use_ok("Xango::Broker::Push");
}

1;