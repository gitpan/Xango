# $Id: Handler.pm 89 2005-10-17 13:25:54Z daisuke $
#
# Copyright (c) 2005 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package XangoTest::SimplePull::Handler;
use strict;
use base qw(XangoTest::BaseHandler);
use POE;

sub initialize
{
    my $self = shift;
    $self->{JOB_RESULT} = {};
    $self->{JOBS} = [];
    $self->SUPER::initialize(@_);
}

sub states
{
    my $self = shift;
    my %states = $self->SUPER::states(@_);

    my $object_states = $states{object_states};
    for my $i (0..scalar(@$object_states) / 2) {
        next unless $object_states->[$i * 2] == $self;

        push @{$object_states->[$i * 2 + 1]},
            qw(retrieve_jobs);
    }

    return %states;
}

sub retrieve_jobs
{
    my($kernel, $obj) = @_[KERNEL, OBJECT];

    # Retrieve one by one
    my $jobs = $obj->jobs;
    return splice(@$jobs, 0, 1);
}

sub handle_response
{
    my($kernel, $obj, $job) = @_[KERNEL, OBJECT, ARG0];

    $obj->job_result->{$job} = Storable::dclone($job);
}

1;