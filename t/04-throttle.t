#!perl
use strict;
use Test::More skip_all => "I can't seem to make this test work";
use lib("t/lib");
BEGIN
{
    sub Xango::DEBUG { 1 }
    require Test::More;
    eval { require HTTP::Server::Simple };

    if ($@) {
        Test::More->import(skip_all => 'HTTP::Server::Simple not available');
    } else {
        Test::More->import(tests => 2);
    }
    use_ok("XangoTest::SimplePush::Handler");
    use_ok("XangoTest::ThrottlePush::Broker");
}

sub _graceful { CORE::exit(1) }
$SIG{$_} = '_graceful' for qw(INT HUP TERM QUIT);

open(SERVER, "$^X t/throttle_server.pl |");

my $child = <SERVER>;
chomp $child;
my $port = <SERVER>;
chomp $port;

ok($child && $port, "Couldn't bind server, skipping.");

my $uri = "http://localhost:$port";
my $handler = XangoTest::SimplePush::Handler->spawn();
my $broker = XangoTest::ThrottlePush::Broker->spawn(
    AutoThrottle => 1,
    DnsCacheClass => 'Cache::MemoryCache',
);

for (1..20) {
    POE::Kernel->post($broker->alias, 'enqueue_job', Xango::Job->new(uri => $uri));
}
print STDERR "POE::Kernel->run called\n";
POE::Kernel->run;
print STDERR "DONE\n";

END
{
    kill TERM => $child if $child;
}
