# $Id: Broker.pm 62 2005-05-21 21:11:12Z daisuke $
#
# Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package Xango::Broker;
use strict;
use HTTP::Request;
use POE;
use Xango::Config;

use constant DEFAULT_HTTP_COMP_CLASS => 'POE::Component::Client::HTTP';
use constant DEFAULT_DNS_COMP_CLASS  => 'POE::Component::Client::DNS';
use constant DEFAULT_HTTP_COMP_ARGS  => [];
use constant DEFAULT_CACHE_CLASS     => 'Cache::FileCache';
use constant DEFAULT_CACHE_ARGS      => {
    namespace => 'DNS',
    default_expires_in => 3 * 3600
};

sub spawn
{
    my $class = shift;
    my %args  = @_;

    my @jobs;
    my %heap = (
        DNS_COMP_ALIAS => 'xango-dns',
        DNS_PENDING    => {},
        PENDING_JOBS   => \@jobs,
        FETCHERS       => {},
        CONFIG_FILE    => $args{conf},
    );

    POE::Session->create(
            heap => \%heap,
            package_states => [
            $class => [
                qw(_start _stop load_config),
                qw(dispatch_job send_fetcher handle_response finalize_job),
                qw(got_dns_response fake_error_response),
                qw(spawn_http_comp fetcher_progress),
                qw(got_sigpipe die_from_sig)
            ]
        ]
    );
}

sub load_config
{
    my($kernel, $heap, $config_file) = @_[KERNEL, HEAP, ARG0];

    if ($heap->{CONFIG_LOADED}) {
        Xango::debug("[load_config]: Reloading config from $config_file");
    }

    Xango::Config->init($config_file, { force_reload => 1});

    my $cache_class =
        Xango::Config->param('DnsCacheClass') || DEFAULT_CACHE_CLASS;
    eval "require $cache_class";
    if ($@) {
        Carp::croak("Failed to load cache class $cache_class: $@");
    }

    my $cache_args = Xango::Config->param('DnsCacheArgs') ;
    if (!$cache_args) {
        if( $cache_class eq DEFAULT_CACHE_CLASS) {
            $cache_args = DEFAULT_CACHE_ARGS;
        } else {
            Carp::croak("You must provide DnsCacheArgs");
        }
    }
    my $cache            = $cache_class->new($cache_args);

    my $job_retrieval_delay = int(Xango::Config->param('JobRetrievalDelay'));
    if ($job_retrieval_delay <= 0) {
        $job_retrieval_delay = 15;
    }

    my $reload           = int(Xango::Config->param('ReloadConfig'));
    if ($reload < 0) {
        $reload = 0;
    }

    my $max_agents       = int(Xango::Config->param('MaxHttpAgents'));
    my $max_silence      = int(Xango::Config->param('MaxSilenceInterval'));
    my $http_timeout     = int(Xango::Config->param('HttpTimeout'));
    my $dns_comp_class   = Xango::Config->param('DnsCompClass') || DEFAULT_DNS_COMP_CLASS;
    my $http_comp_class  = Xango::Config->param('HttpComponentClass') || DEFAULT_HTTP_COMP_CLASS;
    my $http_comp_args   = Xango::Config->param('HttpComponentArgs') || DEFAULT_HTTP_COMP_ARGS;
    if (ref($http_comp_args) eq 'HASH') {
        # coerce it to be an array.
        $http_comp_args = [ %{$http_comp_args} ];
    }

    eval "require $http_comp_class"; die if $@;
    eval "require $dns_comp_class";  die if $@;

    if ($max_agents <= 0) {
        $max_agents = 10;
    }

    if ($max_silence <= 0) {
        $max_silence = 300;
    }

    $heap->{DNS_CACHE}            = $cache;
    $heap->{HTTP_COMP_CLASS}      = $http_comp_class;
    $heap->{HTTP_COMP_ARGS}       = $http_comp_args;
    $heap->{DNS_COMP_CLASS}       = $dns_comp_class;
    $heap->{MAX_HTTP_COMP}        = $max_agents;
    $heap->{MAX_SILENCE_INTERVAL} = $max_silence;
    $heap->{HTTP_TIMEOUT}         = $http_timeout;
    $heap->{JOB_RETRIEVAL_DELAY}  = $job_retrieval_delay;

    $kernel->call('handler', 'load_config', $config_file);

    $heap->{CONFIG_LOADED} ||= 1;
}

sub got_sigpipe
{
    # XXX - This state exists solely to avoid a nasty bug that makes
    # (probably) POE::Component::Client::HTTP vulnerable to misbehaving
    # web servers that decides to kill the socket connection while we're
    # still talking to it. 
    #
    # We basically ignore this error as an unfortunate side effect,
    # and yield to dispatch_job just to make sure that the processing
    # cycle continues
    $_[KERNEL]->yield('dispatch_job');
    $_[KERNEL]->sig_handled();
}

sub die_from_sig
{
    # Note shutdown request
    $_[HEAP]->{SHUTDOWN} ||= time();

    Xango::debug("[die_from_sig]: Received SIG$_[ARG0]. Please wait while we finish up remaining jobs...");

    # Propagate sig to handler
    $_[KERNEL]->signal('handler', $_[ARG0]);

    # But don't let it kill us
    $_[KERNEL]->sig_handled();
}

sub _start
{
    my($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

    # Load config file first
    $kernel->call($session, 'load_config', $heap->{CONFIG_FILE});

    $kernel->alias_set('broker');
    # See 'got_sigpipe' entry elsewhere. very important that we handle
    # this state here.
    $kernel->sig(PIPE => 'got_sigpipe');
    $kernel->sig(INT  => 'die_from_sig', 'INT');
    $kernel->sig(QUIT => 'die_from_sig', 'QUIT');
    $kernel->sig(TERM => 'die_from_sig', 'TERM');
    $kernel->sig(HUP  => 'load_config',  $heap->{CONFIG_FILE});

    $heap->{DNS_COMP_CLASS}->spawn(
        Alias => $heap->{DNS_COMP_ALIAS},
        Timeout => 45
    );

    $kernel->call(
        $session,
        'spawn_http_comp',
        $heap->{MAX_HTTP_COMP} > 10 ? 10 : $heap->{MAX_HTTP_COMP}
    );

    $kernel->yield('dispatch_job');
}

sub _stop
{
    my($kernel, $heap) = @_[KERNEL, HEAP];
    Xango::debug("[_stop]: broker session stopping.");
}

sub spawn_http_comp
{
    my($kernel, $heap, $how_many) = @_[KERNEL, HEAP, ARG0];

    Xango::debug("Spawning $how_many HTTP components");
    my $fetchers = $heap->{FETCHERS};
    my $http_class = $heap->{HTTP_COMP_CLASS};
    my @args       = @{ $heap->{HTTP_COMP_ARGS} };

    for (1..$how_many) {
        my $alias = join("-", "http", time(), rand());
        $http_class->spawn(@args, Alias => $alias);
        my %data;
        $fetchers->{$alias} = \%data;
    }
}

sub dispatch_job
{
    my($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

    return if $heap->{SHUTDOWN};

    my $handler = $kernel->alias_resolve('handler');
    my $jobs    = $heap->{PENDING_JOBS};

    if (&Xango::DEBUG) {
        my $dns_pending = 0;
        my $fetcher_cnt = scalar(keys %{$heap->{FETCHERS}});
        my $pending_cnt = scalar(@{$heap->{PENDING_JOBS}});

        while (my($host, $list) = each %{$heap->{DNS_PENDING}}) {
            $dns_pending += scalar(@$list);
        }

        my $txt = sprintf(<<EOM, $fetcher_cnt, $pending_cnt, $dns_pending);
*****************************************************************
* FETCHERS           : %d
* PENDING            : %d
* PENDING DNS REQS   : %d
*****************************************************************
EOM
        foreach my $line (split(/\n/, $txt)) {
            Xango::debug($line);
        }
    }

    if ($heap->{RELOAD_CONFIG_INTERVAL} && $heap->{LAST_RELOAD} < time() - $heap->{ReLOAD_CONFIG_INTERVAL}) {
        $kernel->call($session, 'load_config', $heap->{CONFIG_FILE});
    }


    my $txt;
    my $pending;
    my $retrieve_done;
    my $dispatch_done;
    my $set_alarm;
    my @deleted_fetchers;
    my $fetchers = $heap->{FETCHERS};

    while (my($http_component, $data) = each %{$fetchers}) {
        # how long has this HTTP component been hanging on this request?
        # if it's more than the set amoutn of time, then remove this
        # component by removing references to it.
        $pending = $kernel->call($http_component, 'pending_requests_count');

        if ($pending) {
            if ($data->{last_request_time} + $heap->{MAX_SILENCE_INTERVAL} < time()) {
                $txt = sprintf(<<EOM, $http_component, scalar($data->{last_request_time}));
*****************************************************************
* !!! INACTIVE HTTP COMPONENT !!!
* ALIAS           : %s
* LAST REQUEST AT : %s
*****************************************************************
EOM
                foreach my $job (values %{$data->{jobs}}) {
                    $kernel->yield('fake_error_response', $job, "Broker Inactivity Timeout");
                }

                Xango::debug($_) for split(/\n/, $txt);
                push @deleted_fetchers, $http_component;
            }
        } else {
            # This is a valid HTTP Component. 
            if (! scalar (@$jobs) && ! $retrieve_done) {
                # if there is a fetcher that's ready to accept, but no jobs
                # see if there are any jobs from the handler. But do this
                # only once!
                Xango::debug("[dispatch_job]: Retrieving new jobs");
                foreach my $job (eval { $kernel->call($handler, 'retrieve_jobs') }) {
                    push @$jobs, $job;
                }
                $retrieve_done = 1;
            }

            # If there are jobs to be dispatched, send it with this fetcher
            if (! keys %{$data->{dispatched}} && scalar (@$jobs)) {
                $dispatch_done++;
                my $job = shift @$jobs;
                $job->{uri} = URI->new($job->{uri});
                $job->{fetcher} = $http_component;
                Xango::debug("[dispatch_job]: dispatch $job->{uri}");
                $kernel->post($handler, 'apply_policy', $job);
                $data->{dispatched}->{$job->{id}} = $job;
            }
        }
    }

    if (&Xango::DEBUG && $dispatch_done) {
        Xango::debug("[dispatch_job]: Dispatched $dispatch_done jobs. ");
    }

    foreach my $http_comp_id (@deleted_fetchers) {
        my $data = delete $fetchers->{$http_comp_id};
        undef $data;
        if ($kernel->detach_child($http_comp_id)) {
            Xango::debug("[dispatch_job]: Failed to detach $http_comp_id: $!");
        }
    }

    if (! $dispatch_done && scalar(@$jobs)) {
        # What, nothing disptched and we have jobs? we need more http
        # components to handle these!
        my $spawn_count = 0;
        my $fcount = scalar(keys %{$fetchers});

        if ($fcount < $heap->{MAX_HTTP_COMP}) {
            if ($fcount == 0) {
                $spawn_count =
                    $heap->{MAX_HTTP_COMP} > 10 ? 10 : $heap->{MAX_HTTP_COMP};
            } elsif ($heap->{MAX_HTTP_COMP} < $fcount * 2) {
                $spawn_count = $heap->{MAX_HTTP_COMP} - $fcount;
            } else {
                $spawn_count = $fcount;
            }
    
            if ($spawn_count > 0) {
                $kernel->call('broker', 'spawn_http_comp', $spawn_count);
            }
        } else {
            Xango::debug("[dispatch_job]: All fetchers busy");
            $set_alarm = 1;
        }
    }

    if (! $dispatch_done && ! scalar (@$jobs)) {
        # argh, no fetcher, no jobs. just set an alarm so that
        # dispatch_job gets called again.
        $set_alarm = 1;
    }

    if ($set_alarm) {
        my @old_alarm = $kernel->alarm_remove($heap->{DISPATCH_ALARM});
        if (@old_alarm && $old_alarm[1] > time()) {
            Xango::debug("[dispatch_job]: Nothing to dispatch, but there's already an alarm");
            Xango::debug("[dispatch_job]:   (to go off at", scalar(localtime($old_alarm[1])), ")");
        } else {
            Xango::debug("[dispatch_job]: Nothing to dispatch, re-dispatch in $heap->{JOB_RETRIEVAL_DELAY} seconds");
            @old_alarm = ('dispatch_job', time() + $heap->{JOB_RETRIEVAL_DELAY});
        }
        $heap->{DISPATCH_ALARM} = $kernel->alarm_set(@old_alarm);
    } 

    if ($dispatch_done) {
        $kernel->yield('dispatch_job');
    }
}

sub fetcher_progress
{
    if (&Xango::DEBUG) {
        my $gen_args  = $_[ARG0];
        my $call_args = $_[ARG1];

        my $uri     = $gen_args->[0]->uri->clone;
        my $tag     = $gen_args->[1];
        if (ref($tag) eq 'HASH' && $tag->{host_name}) {
            $uri->host($tag->{host_name});
        }
        my $got     = $call_args->[0];
        my $tot     = $call_args->[1];
        my $percent = sprintf("%0.2f", ($got / $tot) * 100);
        Xango::debug("[progress]: $uri ($got of $tot bytes, $percent%)");
    }
}

sub send_fetcher
{
    my($kernel, $heap, $job) = @_[KERNEL, HEAP, ARG0];

    if (! $job->{uri}->can('host') || ! $job->{uri}->host) {
        Xango::debug("Red alert! uri->host is not defined!? for uri = $job->{uri}");
        return $kernel->yield(
            'fake_error_response',
            $job,
            "Could not connect to $job->{uri} (internal error)"
        );
    }

    if ($job->{uri}->host !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
        my $host = $job->{uri}->host;
        my $dnscache = $heap->{DNS_CACHE};
        my $ip       = $dnscache->get($host);
        if (!$ip) {
            Xango::debug("[send_fetcher]: No ip for host $host. Making DNS request.");
            $heap->{DNS_PENDING}{$host} ||= [];
            my $list = $heap->{DNS_PENDING}{$host};
            push @$list, $job;
            $kernel->post(
                $heap->{DNS_COMP_ALIAS},
                'resolve',
                'got_dns_response',
                $host
            );
            return;
        }

        if ($ip eq '0.0.0.0') {
            my $response_error = "No address associated with $host";
            $kernel->yield(
                'fake_error_response',
                $job,
                "Could not connect to $job->{uri} ($response_error)"
            );
            return;
        }
        $job->{host_ip} = $ip;
    }

    my $fid = $job->{fetcher};
    if ($job->{host_ip} && $job->{uri}->host !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
        $job->{host_name} = $job->{uri}->host();
        $job->{uri}->host($job->{host_ip});
    }
    my $request = HTTP::Request->new(GET => $job->{uri});
    $kernel->call('handler', 'prep_request', $job, $request);
    if ($job->{host_name}) {
        $request->header(Host => $job->{host_name});
    }

    my $fdata = $heap->{FETCHERS}->{$fid};
    $fdata->{last_request_time} = time();
    $fdata->{jobs}->{$job->{id}} = $job;

    my @args = ($fid,'request','handle_response',$request,$job);
    if (&Xango::DEBUG) {
        push @args, 'fetcher_progress';
    }
    $kernel->post(@args);
}

sub handle_response
{
    my($kernel, $heap, $reqpack, $respack) = @_[KERNEL, HEAP, ARG0, ARG1];

    my $job = $reqpack->[1];

    # put the uri back to hostname, if available
    if ($job->{host_name}) {
        $job->{uri}->host($job->{host_name});
    }
    my $response = $respack->[0];
    my $request  = $reqpack->[0];

    $job->{http_response} = $response;
    if ($request->uri ne $job->{uri}) { # probably DNS
        $request->uri($job->{uri});
    }
    $response->request($request);

    $kernel->post('handler', 'handle_response', $job) or
        die  "Failed to post event 'handle_response' to 'handler'";
    $kernel->yield('finalize_job', $job);
    $kernel->yield('dispatch_job');
}

sub finalize_job
{
    my($kernel, $heap, $job) = @_[KERNEL, HEAP, ARG0];

    $kernel->post('handler', 'finalize_job', $job);

    my $fid = $job->{fetcher};
    my $fdata = $heap->{FETCHERS}->{$fid};
    delete $fdata->{jobs}->{$job->{id}};
    delete $fdata->{dispatched}->{$job->{id}};
    $heap->{FETCHER_STATUS}[$fid]--;
    Xango::debug("[handle_response]: fetcher $fid done");
}

sub got_dns_response
{
    my($self, $kernel, $heap) = @_[OBJECT, KERNEL, HEAP];

    my $request_address = $_[ARG0]->[0];
    my $response_object = $_[ARG1]->[0];
    my $response_error  = $_[ARG1]->[1];

    my $requests = delete $heap->{DNS_PENDING}{$request_address};
    if (!$requests) {
        Xango::debug("Resolved $request_address, but no requests associated to it were found!");
        $kernel->yield('dispatch_job');
        return;
    }

    if (defined $response_object) {
        my $ip;
        foreach my $answer ($response_object->answer()) {
            next unless $answer->type eq 'A';
            $ip = $answer->rdatastr;
            last;
        }

        if ($ip) {
            Xango::debug("[got_dns_response]: $request_address resolved to $ip.");
            $heap->{DNS_CACHE}->set($request_address, $ip);
            foreach my $job (@$requests) {
                $kernel->yield('send_fetcher', $job);
            }
            return; # yay
        }
    }

    # If we got here, everything else is an error.
    # XXX - Make sure that fetcher->{dispatched} is unset
    if (!defined $response_object) {
        # No response - create a fake 500 response, short-cicuit and send
        # the result to the job processor
        foreach my $job (@$requests) {
            delete $heap->{FETCHERS}->{$job->{fetcher}}->{dispatched}->{$job->{id}};
            $kernel->yield(
                'fake_error_response',
                $job,
                "Could not connect to $job->{uri} ($response_error)"
            );
        }
    } else {
        # If we got here, we probably didn't find any 'A' records in the
        # DNS lookup. Treat this as an error as well
        foreach my $job (@$requests) {
            delete $heap->{FETCHERS}->{$job->{fetcher}}->{dispatched}->{$job->{id}};
            $kernel->yield(
                'fake_error_response',
                $job,
                "Could not connect to $job->{uri} ($response_error)"
            );
        }
    }
    my $dnscache = $heap->{DNS_CACHE};
    $dnscache->set($request_address, '0.0.0.0');
    $kernel->yield('dispatch_job');
}

sub fake_error_response
{
    my($kernel, $job, $message) = @_[KERNEL, ARG0, ARG1];

    my $response = HTTP::Response->new(500);
    $response->content(<<EOHTML);
<HTML>
<HEAD><TITLE>An Error Occurred</TITLE></HEAD>
<BODY>
<H1>An Error Occurred</H1>
500 $message
</BODY>
</HTML
EOHTML

    my $request = HTTP::Request->new(GET => $job->{uri});
    $request->content('DUMMY-REQUEST');
    $response->request($request);
    $kernel->yield('handle_response', [ $request, $job ], [ $response ]);
}

1;

__END__

=head1 NAME

Xango::Broker - Broker HTTP Requests

=head1 SYNOPSIS

  use Xango::Broker;
  use MyHandler;
  MyHandler->spawn();
  Xango::Broker->spawn();
  POE::Kernel->run();

  # or,
  xango -h MyHandler

=head1 DESCRIPTION

Xango is a generic web crawler framework written using POE 
(http://poe.perl.org), a cooperative multitasking framework.

Xango::Broker is Xango's main POE component but it doesn't do much by itself:
Instead, you need to write a handler that does all the application-specific
work where most of the interesting bits are done. 

Xango::Broker is mainly responsible for three things: (1) Setting up the
general environment, (2) providing the processig pipeline for the most
common crawler behavior, and (3) handling the HTTP fetches as well as their
states. Your handler will be part of (2) above, as the component that is
responsible for the following things:

=over 4

=item Provide the data to fetch

You need to tell Xango::Broker what to fetch :)

=item Handle the HTTP response.

...And you need to process the response that you get after Xango::Broker
fetches the requested URI.

=back

Please see the section L<HANDLER API|HANDLER API> for more details.

=head1 CONFIGURATION VARIABLES

Configuration variables are written in YAML format. Please see the documentation
for L<YAML|YAML> for more information on how to write the configuration file.

If your custom web crawler requires more configuration parameters, you can
safely specify more stuff in the same config file, so as long as it does
not clash with an already existing parameter name that is requried by 
Xango::Broker.

To use these configuration variables, you need to use Xango::Config:

  use Xango::Config qw(filename.conf);
  # or
  Xango::Config->init('filename.conf');

or, you can pass it to the Xango::Broker's spawn() method :

  Xango::Broker->spawn(conf => 'filename.conf');

Once initialized, you may refer to the same Xango::Config instance from
anywhere in your code. Please see L<Xango::Config|Xango::Config> for more
details.

=head2 HttpComponentClass (string)

=over 4

Class name of the POE component that handles HTTP communication. You may
specify any class, so as long as it has interfaces matching
POE::Component::Client::HTTP.

Defaults to 'POE::Component::Client::HTTP'

=back

=head2 HttpComponentArgs (list or hash)

=over 4

Arguments that are passed to the spawn() method of the HTTP component class.
You almost always want to specify the 'Timeout' parameter if you're using
POE::Component::Client::HTTP (or the like)

Note that you may not specify the 'Alias' parameter. This is internally
used by Xango::Broker. If you specify it, it will silently be ignored

=back

=head2 DnsCacheClass (string)

=over 4

Xango internally caches DNS lookup results to avoid the overhead of having
to query for IP address. This configuration variable specifies the
class name of the cache object to hold DNS query results. Defaults to
L<Cache::FileCache|Cache::FileCache>.

=back

=head2 DnsCacheArgs (hash)

=over 4

Arguments to pass to the cache constructor. You must provide this if you
are using anything other than Cache::FileCache as your cache class.

=back

=head2 MaxHttpAgents (integer)

=over 4

The number of concurrent http agents (i.e. the number of
POE::Component::Client::HTTP sessions) that are allowed. The default is 10,
but for anything other than a toy application, something in the order of
50 ~ 100 is the recommended value.

Unless this number is less than 10, the broker starts with 10 sessions,
and successively grows the pool of agents when there are not enough
agents to handle the currently available jobs, until the maximum is reached.

If the max is less than 10, the starting number if equal to the max.

=back

=head2 MaxSilenceInterval (integer)

=over 4

The number of seconds that we allow an agent to be inactive for. Once a fetcher
session is inactive for this much amount of time, the sessions is stopped
via detach_child(). The default is 300 seconds.

=back

=head2 JobRetrievalDelay (integer)

=over 4

The number of seconds to wait between calls to 'retrieve_job' state of the
handler session. The default is 15 seconds.

=back

=head2 ReloadConfig (integer)

=over 4

The number of seconds to wait before reloading configuration parameters from
the config file. If set to 0, reload is disabled.

=back

=head1 HANDLER API

The handler, which is where your application specific logic goes, must
implement events that are listed below.

Note that the handler must be alias appropriately, as 'handler'. 
Don't forget to put something like this in your handler session's _start() 
method so that the alias is set properly:

  sub _start
  {
     my($kernel) = @_[KERNEL];
     $kernel->alias_set('handler');
  }

  sub _stop
  {
     my($kernel) = @_[KERNEL];
     $kernel->alias_remove('handler');
  }

Below are the states that are recognized in the handler session. Those states
with a (*) next to them are mandatory:

=head2 load_config

=over 4

This state is called whenever the configuration is (re)loaded from a file.
Use this state to refresh variables that are specific to the handler.

=back

=head2 retrieve_jobs (*)

=over 4

This state is responsible for retrieve jobs to be processed by Xango
from wherever you decide to store your original data (RDBMS, file system,
manual user input, etc).

It should return a list of hashref, which must contain at least 1 element
named 'uri'. You may add any other elements, except 'id', 'fetcher', 
'host_ip', and 'host_name', which are used internally by Xango.
(However, you are welcome to use these values as read-only variables).

  sub retrieve_jobs
  {
     while (my $uri = get_next_uri()) {
        push @jobs_to_be_processed, {
            uri => $uri,
            my_var => $my_var,
            my_other_var => $my_other_var
        };
     }
     return @jobs_to_be_processed;
  }

This state is called as a synchronous call via POE::Kernel-E<gt>call(),
so don't take forever to get the jobs to be processed!

=back

=head2 apply_policy (*)

=over 4

This receives a job hash, and is supposed to figure if the particular job
should be processed at all. Use this to apply black policy rules at the
broker level (NOTE: if at all possible, do this at the storage level, such
as a RDBMS server's stored procedure, as complicated policies will probably
slow the broker down significantly).

At the very least, if you are not applying any policies, write a stub
pass-through state like below so that you just call the next state
in the processing chain:

  sub apply_policy
  {
     my($kernel, $fetcher, $job) = @_[KERNEL, ARG0, ARG1];
     $kernel->post('broker', 'send_fetcher', $fetcher, $job);
  }

Note, you *have* to call 'send_fetcher' in order for the job to be processed
at all. If you otherwise do not wish to process this job, post to the
broker session's 'finalize_job' state

  sub apply_policy
  {
     my($kernel, $job) = @_[KERNEL, ARG0];
     if ( $DONT_PROCESS ) {
        $kernel->post('broker', 'finalize_job', $job);
     } else {
        $kernel->post('broker', 'send_fetcher', $job);
     }
  }

The job hash will be available in ARG0

=back

=head2 prep_request

=over 4

Called right before the request is sent, you are given a chance to muck with
the HTTP request in this state.

The job hash will be available in ARG0, the HTTP::Request object will be
available in ARG1

=back

=head2 handle_response (*)

=over 4

As the name states, this state should handle the job, after the job's
URI has been fetched. The HTTP::Response object is stored under the
'http_response' slot in the job, and you are free to do whatever you want
with it -- because Xango doesn't do anything else with that job after
this state. 

It is up to you to cook this piece of data, and store the results somewhere
(or, discard them).

The job hash will be available in ARG0

=back

=head2 finalize_job

=over 4

This is sort of like a destructor for the job. The broker does its own
cleanup, and then sends the job to the handler's 'finalize_job' state so
that application-specific cleanup can be performed.

The job hash will be available in ARG0

=back

=head1 TODO

=over 4

=item Tests

We need tests...

=item How-To Docs

Documentation on how to implement a toy crawler is necessary

=back 4

=head1 BUGS

Plenty, I'm sure. Please report bugs via RT http://rt.cpan.org/NoAuth/Bugs.html?Dist=Xango

=head1 SEE ALSO

L<POE|POE>

=head1 AUTHOR

Copyright 2005 Daisuke Maki E<lt>dmaki@cpan.orgE<gt>. All rights reserved.
Development funded by Brazil, Ltd. E<lt>http://b.razil.jpE<gt>

=cut 
