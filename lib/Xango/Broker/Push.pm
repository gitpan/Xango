# $Id: Push.pm 87 2005-10-17 08:52:38Z daisuke $
#
# Copyright (c) 2005 Daisule Maki <dmaki@cpan.org>
# All rights reserved.

package Xango::Broker::Push;
use strict;
use base qw(Xango::Broker::Base);
use POE;

sub states
{
    my $self   = shift;
    my %states = $self->SUPER::states(@_);

    my $object_states = $states{object_states};
    for my $i (0..scalar(@$object_states) / 2) {
        next unless $object_states->[$i * 2] == $self;

        push @{$object_states->[$i * 2 + 1]}, 
            qw(enqueue_job flush_queue);
    }
    return %states;
}

sub initialize
{
    my $self = shift;
    $self->{JOB_QUEUE} ||= [];
    $self->SUPER::initialize(@_);
}

sub spawn_http_comp
{
    my($kernel, $obj) = @_[KERNEL, OBJECT];

    $obj->can('SUPER::spawn_http_comp')->(@_);
    $kernel->yield('flush_queue');
}

sub enqueue_job
{
    my($kernel, $session, $obj, $job) = @_[KERNEL, SESSION, OBJECT, ARG0];
    Xango::debug("[enqueue_job]: enqueue");

    if (! $obj->check_job_type($job)) {
        Xango::debug("[enqueue_job]: Cannot allow job type ". ref($job));
        return;
    }

    if (! eval { $job->uri->isa('URI') })  {
        $job->uri(URI->new($job->uri));
    }

    my $fetchers = $obj->fetchers;
    if (keys %$fetchers) {
        $kernel->call($session, 'dispatch_to_lightest_load', $job);
    } else {
        my $q = $obj->job_queue;
        push @$q, $job;
    }
}

sub flush_queue
{
    my($kernel, $session, $obj) = @_[KERNEL, SESSION, OBJECT];
    my $q = $obj->job_queue;
    for my $job (@$q) {
        $kernel->call($session, 'dispatch_to_lightest_load', $job);
    }
    @$q = ();
}

sub dispatch_job
{
    my($kernel, $heap, $job) = @_[KERNEL, HEAP, ARG0];

    # In this scenario, assume that the job has already been checked for
    # validity (it is the caller sessions' responsibility to make sure that
    # the job is a-ok). So the only thing that dispatch_job will do is to
    # push the job in the to incoming queue.

}

# This state should only be called if 
sub check_queue
{
    my($kernel, $heap) = @_[KERNEL, HEAP];

    # Check if the queue contains more jobs to process. If 
    
}

1;
__END__

=head1 NAME

Xango::Broker::Push - Xango's Push-Crawler

=head1 SYNOPSIS

  use Xango::Broker::Push;

  Xango::Broker::Push->spawn(
    
  );

  # in some other session...
  foreach my $job (@jobs) {
    $kernel->post($broker_session, 'dispatch_job', $job);
  }

=head1 DESCRIPTION

Xango::Broker::Push implements the push-model crawler for Xango. A separate
session must notify the crawler that there are jobs to be fetched.

This is the preferred model if:

  (a) Crawling is triggered by an event, not in a periodic manner
  (b) You have long intervals between when jobs are available
  (c) You have external entities that can work in a separate process to generate
the list of jobs to be processed

=head1 SEE ALSO

L<Xango::Broker::Base> L<Xango::Broker::Pull>

=head1 AUTHOR

Copyright (c) 2005 Daisuke Maki E<lt>dmaki@cpan.orgE<gt>. All rights reserved.
Development funded by Brazil, Ltd. E<lt>http://b.razil.jpE<gt>

=cut