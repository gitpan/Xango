#!perl
use strict;
use Test::More;
use lib("t/lib");
use XangoTest::SimplePull;
use XangoTest::Util qw(check_prereqs);

eval { check_prereqs() };
if ($@) {
    plan skip_all => $@;
}
plan(tests => 3);

my @jobs = (Xango::Job->new(uri => URI->new('http://www.cpan.org')));
my $handler = XangoTest::SimplePull::Handler->spawn(jobs => [@jobs]);

my $broker  = XangoTest::SimplePull::Broker->spawn();

# States to verify
my @states = qw(handle_http_response);

POE::Kernel->run();

# now verify..
foreach my $job (@jobs) {
    my $data = $handler->job_result->{$job};
    ok($data);

    my $response = $data->notes('http_response');
    ok($response);
    ok(eval { $response->is_success }, "Response is a success");
}

