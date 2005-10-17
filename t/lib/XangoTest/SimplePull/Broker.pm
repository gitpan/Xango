# $Id: Broker.pm 89 2005-10-17 13:25:54Z daisuke $

package XangoTest::SimplePull::Broker;
use strict;
use base qw(Xango::Broker::Pull);
use POE;

sub initialize
{
    my $self = shift;
    $self->SUPER::initialize(@_, JobRetrievalDelay => 5);
}

sub pull_jobs
{
    my($obj) = @_[OBJECT];
    my $ret = $obj->can('SUPER::pull_jobs')->(@_);
    if (!$ret) {
        $obj->shutdown(1);
    }
    return $ret;
}

1;