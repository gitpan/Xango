# $Id: Push.pm 106 2006-05-01 02:33:25Z daisuke $
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
            qw(enqueue_job flush_pending busy_loop);
    }
    return %states;
}

sub initialize
{
    my $self = shift;
    $self->{JOB_QUEUE} ||= [];
    $self->{LOOP}        = 0;
    $self->SUPER::initialize(@_);
}

sub spawn_http_comp
{
    my($kernel, $obj) = @_[KERNEL, OBJECT];

    $obj->can('SUPER::spawn_http_comp')->(@_);
    $kernel->yield('flush_pending');
}

sub enqueue_job
{
    my($kernel, $obj, $job) = @_[KERNEL, OBJECT, ARG0];
    Xango::debug("[enqueue_job]: enqueue");

    if (! $obj->check_job_type($job)) {
        Xango::debug("[enqueue_job]: Cannot allow job type ". ref($job));
        return;
    }

    $kernel->alarm_remove($obj->{LOOP_ALARM});
    delete $obj->{LOOP_ALARM};

    if (! eval { $job->uri->isa('URI') })  {
        $job->uri(URI->new($job->uri));
    }
    my $q = $obj->job_queue;
    push @$q, $job;

    if (! $obj->{FLUSH_PENDING}++) {
        $kernel->yield('flush_pending');
    }
}

sub flush_pending
{
    my($kernel, $session, $obj) = @_[KERNEL, SESSION, OBJECT];

    delete $obj->{FLUSH_PENDING};
    return if $obj->shutdown;

    my $fetchers = $obj->fetchers;

    my $q = $obj->job_queue;
    my $dispatched_once;
    for (my $i = 0; $i < @$q; $i++) {
        # Only allow 1 job per fetcher
        my $job = $q->[$i];
        my $dispatched = 0;

        while (my($fetcher_id, $data) = each %$fetchers) {
            my $job_count = keys %{$data->{jobs}};
            next if ($job_count);

            $dispatched = 1;
            $dispatched_once++;
            $kernel->call($session, 'dispatch_to_lightest_load', $job);
            splice(@$q, $i, 1);
            $i--;

            last;
        }

        last if ! $dispatched;
    }

    if (!$dispatched_once && $obj->loop && !$obj->{LOOP_ALARM}) {
        $obj->{LOOP_ALARM} = $kernel->alarm_set('busy_loop', time() + 30)
    }
}

sub finalize_job
{
    my($kernel, $session, $obj, $job) = @_[KERNEL, SESSION, OBJECT, ARG0];

    $obj->can('SUPER::finalize_job')->(@_);

    my $q = $obj->job_queue;
    if (@$q > 0) {
        Xango::debug("[finalize_job]: We have more jobs. Trying to flush...");
        $kernel->yield('flush_pending');
    } elsif ($obj->loop && !$obj->{LOOP_ALARM}) {
        $obj->{LOOP_ALARM} = $kernel->alarm_set('busy_loop', time() + 30)
    }

    $kernel->alarm_set('fake', time() + 65) unless $obj->{FAKE}++;
}

sub busy_loop
{
    # set another alarm
    $_[OBJECT]->{LOOP_ALARM} = $_[KERNEL]->alarm_set('busy_loop', time() + 30);
}

1;
__END__

=head1 NAME

Xango::Broker::Push - Xango's Push-Crawler

=head1 SYNOPSIS

  use Xango::Broker::Push;

  Xango::Broker::Push->spawn(
    Loop => 1
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

=head1 PARAMETERS

=head2 Loop (boolean)

If true, the broker session will continue even when the dispatch queue is
empty. By default the Push crawler stops when the queue is exhausted, but
you can set this to true if you know there are more jobs coming later.

When you set this option, use the 'shutdown' state from elsewhere to stop
the broker session.

=head1 STATES

=head2 enqueue_job($job)

Enqueues a job to be processed.

=head2 flush_pending

flushes pending jobs, if possible

=head2 finalize_job

=head1 SEE ALSO

L<Xango::Broker::Base> L<Xango::Broker::Pull>

=head1 AUTHOR

Copyright (c) 2005 Daisuke Maki E<lt>dmaki@cpan.orgE<gt>. All rights reserved.
Development funded by Brazil, Ltd. E<lt>http://b.razil.jpE<gt>

=cut