#!perl
use Test::More;
BEGIN {
    eval "use Test::Pod";
    eval "use Test::Pod::Coverage";
    if ($@) {
        plan(skip_all => "Test::Pod::Coverage required for testing POD");
        eval "sub pod_coverage_ok {}";
    } else {
        plan(tests    => 6);
    }
}

pod_coverage_ok('Xango');
pod_coverage_ok('Xango::Broker::Base');
pod_coverage_ok('Xango::Job');
pod_coverage_ok('Xango::Config');
foreach my $module qw(Xango::Broker::Pull Xango::Broker::Push) {
    pod_coverage_ok($module, { trustme => [
        'initialize', 'states', 'spawn_http_comp', 'create_http_comp_data' ] });
}
