# $Id: Pull.pm 102 2006-04-17 06:04:21Z daisuke $
#
# Copyright (c) 2005 Daisule Maki <dmaki@cpan.org>
# All rights reserved.

package Xango::Broker::Pull;
use strict;
use base qw(Xango::Broker::Base);
use constant HTTP_COMP_READY      => 0x01;
use constant HTTP_COMP_RESPONSIVE => 0x02;
use POE;

sub initialize
{
    my $self = shift;
    my %args = @_;
    $self->SUPER::initialize(%args);
    $self->{DISPATCH_ALARM}       = undef;
    $self->{JOB_RETRIEVAL_DELAY}  = $args{JobRetrievalDelay}
        if $args{JobRetrievalDelay};
    $self->{MAX_SILENCE_INTERVAL} = $args{MaxSilenceInterval}
        if $args{MaxSilenceInterval};

    $self->{JOB_RETRIEVAL_DELAY}  ||= 30;
    $self->{MAX_SILENCE_INTERVAL} ||= 900;
}

sub states
{
    my $self   = shift;
    my %states = $self->SUPER::states(@_);

    my $object_states = $states{object_states};
    for my $i (0..scalar(@$object_states) / 2) {
        next unless $object_states->[$i * 2] == $self;

        push @{$object_states->[$i * 2 + 1]},
            qw(pull_jobs get_ready_fetchers get_http_comp_state dispatch_job);
    }
    return %states;
}

sub _start
{
    my($kernel, $obj) = @_[KERNEL, OBJECT];
    $obj->can('SUPER::_start')->(@_);

    # I'm a pull parser, so go ahead and try to pull
    $kernel->yield('dispatch_job');
}

sub create_http_comp_data
{
    return { jobs => {} };
}

# Pull jobs from the handler session
sub pull_jobs
{
    my($kernel, $obj) = @_[KERNEL, OBJECT];
    my $handler = $kernel->alias_resolve($obj->handler_alias);
    my $jobs    = $obj->jobs_pending();
    my @list    = $kernel->call($handler, 'retrieve_jobs');
    Xango::debug("[pull_jobs]: Pulled (", scalar(@list), ")");
    if (@list) {
        push @$jobs, @list;
    }
    return scalar(@list);
}

sub get_http_comp_state
{
    my($kernel, $obj, $comp) = @_[KERNEL, OBJECT, ARG0];

    my $fetchers = $obj->fetchers();
    my $data     = $fetchers->{$comp};
    my $ret      = scalar(keys %{$data->{jobs}}) ? 0 : HTTP_COMP_READY;

    if (!$data || $data->{load_request_time} <= time() - $obj->max_silence_interval) {
        $ret += HTTP_COMP_RESPONSIVE;
    }
    return $ret;
}

sub get_ready_fetchers
{
    my($kernel, $session, $obj) = @_[KERNEL, SESSION, OBJECT];

    my @ready_fetchers;
    my @delete_fetchers;
    my $fetchers = $obj->fetchers();
    foreach my $http_comp (keys %{$fetchers}) {
        my $state = $kernel->call($session, 'get_http_comp_state', $http_comp);

        if ($state & HTTP_COMP_READY) {
            push @ready_fetchers, $http_comp;
        } elsif (! ($state & HTTP_COMP_RESPONSIVE)) {
            push @delete_fetchers, $http_comp;
        }
    }

    foreach my $comp (@delete_fetchers) {
        $kernel->call($session, 'signal_http_comp', $comp);
    }

    return @ready_fetchers;
}

sub dispatch_job
{
    my($kernel, $obj, $session) = @_[KERNEL, OBJECT, SESSION];
    # pull-crawler, so we need to periodically call this method to make
    # sure the session don't stop

    return if $obj->shutdown;

    my @ready_fetchers = $kernel->call($session, 'get_ready_fetchers');
    my $dispatch_done = 0;
    my $set_alarm = 0;
    my $fetchers = $obj->fetchers;
    my $jobs     = $obj->jobs_pending;

    if (@ready_fetchers && !@$jobs) {
        $kernel->call($session, 'pull_jobs');
    }

    if (@ready_fetchers && @$jobs) {
        foreach my $http_comp (@ready_fetchers) {
            next unless @$jobs;

            my $job = shift @$jobs;
            $job->notes(fetcher => $http_comp);
            $kernel->call($session, 'dispatch_http_fetch', $job);
        }
        $dispatch_done = 1;
    }

    if (!$dispatch_done) {
        if (@$jobs) {
            # there are available fetchers, but no jobs. spawn more 
            $kernel->call($session, 'adjust_fetcher_count');
        }
        $set_alarm = 1;
    } 

    if ($dispatch_done) {
        # Dispatch again, if we were able to dispatch
        $kernel->yield('dispatch_job');
    } elsif ($set_alarm) {
        my @old_alarm = $kernel->alarm_remove($obj->dispatch_alarm);
        if (@old_alarm && $old_alarm[1] > time()) {
            my $msg = sprintf(<<'            EOM', scalar(localtime($old_alarm[1])));
            [dispatch_job] Nothing to dispatch, but there's already an alarm
            [dispatch_job]   (to go off at %s)
            EOM
            foreach my $line (split(/\n/, $msg)) {
                Xango::debug($line);
            }
        } else {
            my $delay = $obj->job_retrieval_delay;
            Xango::debug("[dispatch_job]: Nothing to dispatch, re-dispatch in $delay seconds");
            @old_alarm = ('dispatch_job', time() + $delay);
        }
        $obj->dispatch_alarm($kernel->alarm_set(@old_alarm));
    }
}

1;

__END__

=head1 NAME

Xango::Broker::Pull - Xango's Pull-Crawler

=head1 SYNOPSIS

  use Xango::Broker::Pull;
  Xango::Broker::Pull->spawn(
    ...
  );

=head1 DESCRIPTION

Xango::Broker::Pull implements the pull-model crawler for Xango, where
jobs that need to be fetched are pulled from a source periodically.

=head1 METHODS

=head2 new

new() accepts the following parameters, which can also be written in an
config file used by L<Xango::Config|Xango::Config>. If you use a config file,
then the values in the config file will be treated as the default, and
the parameters passed to new() can override them.

=over 4

=item JobRetrievalDelay (integer)

The number of seconds to wait between calls to 'retrieve_job' state of the
handler session. The default is 15 seconds.

=item MaxSilenceInterval (integer)

The number of seconds that we allow an agent to be inactive for. Once a fetcher
session is inactive for this much amount of time, the sessions is stopped
via detach_child(). The default is 300 seconds.

=back

=head2 states

Inherited from Xango::Broker::Base.

=head1 STATES

=head2 dispatch_job

Entry point.

=head2 pull_jobs

Interface to ask the handler to pull new jobs to be processed

=head2 get_http_comp_state

=head2 get_ready_fetchers

=head1 SEE ALSO

L<Xango::Broker::Base|Xango::Broker::Base>, 
L<Xango::Broker::Push|Xango::Broker::Push>

=head1 AUTHOR

Copyright (c) 2005 Daisuke Maki E<lt>dmaki@cpan.orgE<gt>. All rights reserved.
Development funded by Brazil, Ltd. E<lt>http://b.razil.jpE<gt>

=cut