#!perl
use strict;
use Test::More (tests => 11);

BEGIN
{
    use_ok("Xango");
    use_ok("Xango::Broker::Pull");
    use_ok("Xango::Broker::Push");
}

my %pull_args = (
    Alias => {
        method => 'alias',
        value  => 'pooper',
    },
    JobRetrievalDelay => {
        method => 'job_retrieval_delay',
        value  => 1234,
    },
    HandlerAlias => {
        method => 'handler_alias',
        value  => 'handler_poo',
    },
    MaxHttpComp => {
        method => 'max_http_comp',
        value  => 365,
    },
    HttpCompClass => {
        method => 'http_comp_class',
        value  => 'HogeHttp',
    },
    HttpCompArgs => {
        method => 'http_comp_args',
        value  => [ 'poop' => 1 ]
    },
    MaxSilenceInterval => {
        method => 'max_silence_interval',
        value  => 1234,
    },
);

my $pull = Xango::Broker::Pull->new(
    map { ($_ => $pull_args{$_}->{value}) } keys %pull_args);

while (my($key, $data) = each %pull_args) {
    my $method = $data->{method};
    if (ref($data->{value})) {
        is_deeply($pull->$method, $data->{value});
    } else {
        is($pull->$method, $data->{value});
    }
}

delete $pull_args{Alias};
$pull = Xango::Broker::Pull->new(
    map { ($_ => $pull_args{$_}->{value}) } keys %pull_args);

is($pull->alias, 'broker');

1;