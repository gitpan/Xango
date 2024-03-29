#!perl
use strict;
use Test::More;

use lib("t/lib");
use XangoTest::SimplePush;
use XangoTest::Util qw(check_prereqs);

eval { check_prereqs() };
if ($@) {
    plan skip_all => $@;
}
plan tests => 8;

my $handler = XangoTest::SimplePush::Handler->spawn();
my $broker  = XangoTest::SimplePush::Broker->spawn(
    DnsCacheClass => 'Cache::MemoryCache',
);

# States to verify
my @states = qw(handle_http_response);
my @jobs = (
    Xango::Job->new(uri => URI->new('http://www.cpan.org')),
    Xango::Job->new(uri => URI->new('http://search.cpan.org')),
);

foreach my $job (@jobs) {
    POE::Kernel->post($broker->alias, 'enqueue_job', $job);
}

POE::Kernel->run();

# now verify..
foreach my $job (@jobs) {
    my $data = $handler->job_result->{$job};
    my $response = $data->notes('http_response');
    ok($data);
    ok($response);
    is($data->uri, $job->uri, "URI ok");
    ok(eval { $response->is_success }, "Response is a success");
}


