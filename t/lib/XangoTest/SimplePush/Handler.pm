# $Id: Handler.pm 105 2006-04-26 09:12:24Z daisuke $
#
# Copyright (c) 2005 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package XangoTest::SimplePush::Handler;
use strict;
use base qw(XangoTest::BaseHandler);
use POE;

sub initialize
{
    my $self = shift;
    $self->{JOB_RESULT} = {};
    $self->SUPER::initialize(@_);
}

sub states
{
    my $self = shift;
    my %states = $self->SUPER::states(@_);

    my $object_states = $states{object_states};
    for my $i (0..scalar(@$object_states) / 2) {
        next unless $object_states->[$i * 2] == $self;

#        push @{$object_states->[$i * 2 + 1]}, 
    }

    return %states;
}

sub handle_response
{
    my($kernel, $obj, $job) = @_[KERNEL, OBJECT, ARG0];

    $obj->job_result->{$job} = Storable::dclone($job);
    $kernel->call('broker', 'shutdown_broker');
}

1;
