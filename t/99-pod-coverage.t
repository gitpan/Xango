use Test::More;
eval "use Test::Pod";
eval "use Test::Pod::Coverage";
plan(skip_all => "Test::Pod::Coverage required for testing POD") if $@;
plan(tests    => 6);

pod_coverage_ok('Xango');
pod_coverage_ok('Xango::Broker::Base');
pod_coverage_ok('Xango::Job');
pod_coverage_ok('Xango::Config');
foreach my $module qw(Xango::Broker::Pull Xango::Broker::Push) {
    pod_coverage_ok($module, { trustme => [
        'initialize', 'states', 'spawn_http_comp', 'create_http_comp_data' ] });
}
