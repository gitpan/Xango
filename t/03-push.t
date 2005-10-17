#!perl
use strict;
use Test::More (tests => 3);

use lib("t/lib");
use XangoTest::SimplePush;

my $handler = XangoTest::SimplePush::Handler->spawn();
my $broker  = XangoTest::SimplePush::Broker->spawn();

# States to verify
my @states = qw(handle_http_response);
my @jobs = (
    Xango::Job->new(uri => URI->new('http://www.cpan.org'))
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
    ok(eval { $response->is_success }, "Response is a success");
}


