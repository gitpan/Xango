# $Id: Push.pm 101 2006-04-01 13:49:04Z daisuke $
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
            qw(enqueue_job flush_pending);
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
    $kernel->yield('flush_pending');
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
    my $q = $obj->job_queue;
    push @$q, $job;

    if (! $obj->{FLUSH_PENDING}++) {
        $kernel->post($session, 'flush_pending');
    }
}

sub flush_pending
{
    my($kernel, $session, $obj) = @_[KERNEL, SESSION, OBJECT];

    delete $obj->{FLUSH_PENDING};

    my $fetchers = $obj->fetchers;

    my $q = $obj->job_queue;
    for (my $i = 0; $i < @$q; $i++) {
        # Only allow 1 job per fetcher
        my $job = $q->[$i];
        my $dispatched = 0;

        while (my($fetcher_id, $data) = each %$fetchers) {
            my $job_count = keys %{$data->{jobs}};
            next if ($job_count);

            $dispatched = 1;
            $kernel->call($session, 'dispatch_to_lightest_load', $job);
            splice(@$q, $i, 1);
            $i--;

            last;
        }

        last if ! $dispatched;
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
    }
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