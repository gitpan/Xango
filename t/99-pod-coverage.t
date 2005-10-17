use Test::More;
eval "use Test::Pod";
eval "use Test::Pod::Coverage";
plan(skip_all => "Test::Pod::Coverage required for testing POD") if $@;
plan(tests    => 1);

my $opts = { trustme => [ 'initialize' ]};

foreach my $module qw(Xango) {
    pod_coverage_ok($module, $opts);
}
