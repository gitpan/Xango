use strict;
use lib("t/lib");
use XangoTest::ThrottlePush::Server;
sub _graceful { CORE::exit(1) };

$| = 1;

my $s = XangoTest::ThrottlePush::Server->new();
{
    $SIG{$_} = '_graceful' for qw(INT HUP QUIT TERM);
    my $root = "http://localhost:" . $s->port;

    print $$, "\n";
    print $root, "\n";
}
$s->run;

