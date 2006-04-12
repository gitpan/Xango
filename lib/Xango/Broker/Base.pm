# $Id: Base.pm 99 2006-03-04 01:30:59Z daisuke $
#
# Copyright (c) 2005 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package Xango::Broker::Base;
use strict;
use HTTP::Request;
use POE;
use Xango;
use Xango::Config;
use Xango::Job;

our $AUTOLOAD;
use constant DEFAULT_HTTP_COMP_CLASS => 'POE::Component::Client::HTTP';
use constant DEFAULT_DNS_COMP_CLASS  => 'POE::Component::Client::DNS';
use constant DEFAULT_HTTP_COMP_ARGS  => [];
use constant DEFAULT_DNS_CACHE_CLASS => 'Cache::FileCache';
use constant DEFAULT_DNS_CACHE_ARGS  => {
    namespace => 'DNS',
    default_expires_in => 3 * 3600
};

sub new
{
    my $class = shift;

    my $self  = bless {}, $class;
    $self->initialize(@_);
    return $self;
}

sub initialize
{
    my $self = shift;
    my %args = @_;

    if ($args{ConfigFile}) {
        my $config = Xango::Config->init($args{ConfigFile});
        $self->_load_config($config);
    }

    # Set values provided by %args. This overrides the config file
    $self->{ALIAS}                = $args{Alias} if exists $args{Alias};
    $self->{DNS_CACHE_ARGS}       = $args{DnsCacheArgs}
        if exists $args{DnsCacheArgs};
    $self->{DNS_CACHE_CLASS}      = $args{DnsCacheClass}
        if exists $args{DnsCacheClass};
    $self->{DNS_CACHE_ARGS_DEREF} = $args{DnsCacheArgsDeref}
        if $args{DnsCacheArgsDeref};
    $self->{DNS_COMP_ALIAS}       = $args{DnsCompAlias} if $args{DnsCompAlias};
    $self->{DNS_COMP_CLASS}       = $args{DnsCompClass} if $args{DnsCompClass};
    $self->{HANDLER_ALIAS}        = $args{HandlerAlias} if $args{HandlerAlias};
    $self->{HTTP_COMP_CLASS}      = $args{HttpCompClass} if $args{HttpCompClass};
    $self->{HTTP_COMP_ARGS}       = $args{HttpCompArgs} if $args{HttpCompArgs};
    $self->{MAX_HTTP_COMP}        = $args{MaxHttpComp} if $args{MaxHttpComp};

    # Set defaults.
    $self->{ALIAS}             ||= 'broker';
    $self->{CONFIG_FILE}       ||= undef;
    $self->{DNS_CACHE_CLASS}   ||= DEFAULT_DNS_CACHE_CLASS;
    $self->{DNS_CACHE_ARGS}    ||= DEFAULT_DNS_CACHE_ARGS;
    if (!exists $self->{DNS_CACHE_ARGS_DEREF}) {
        $self->{DNS_CACHE_ARGS_DEREF} = 0;
    }
    $self->{DNS_COMP_ALIAS}    ||= 'dns_resolver';
    $self->{DNS_COMP_CLASS}    ||= DEFAULT_DNS_COMP_CLASS;
    $self->{DNS_PENDING}         = {}; # Non-configurable
    $self->{FETCHERS}            = {}; # Non-configurable
    $self->{HANDLER_ALIAS}     ||= 'handler';
    $self->{HTTP_COMP_CLASS}   ||= DEFAULT_HTTP_COMP_CLASS;
    $self->{HTTP_COMP_ARGS}    ||= [];
    $self->{JOBS_PENDING}        = []; # Non-configurable
    $self->{MAX_HTTP_COMP}     ||= 10;
    $self->{SHUTDOWN}            = 0;  # Non-configurable
    $self->{STRICT_JOB_TYPE}   ||= 'Xango::Job';
    $self->{UNDEF_ON_FINALIZE} ||= 0;

    my $k_munge;
    foreach my $k (keys %args) {
        $k_munge = $k;
        $k_munge =~ s/([a-z])([A-Z])/$1_$2/g;
        $self->{uc ($k_munge)} = $args{$k};
    }
}

sub _load_config
{
    my($self, $config) = @_;

    $self->{ALIAS} = $config->param('BrokerAlias');

    my $set = sub {
        my $p = shift;
        my $c = $p;

        $c =~ s/([a-z])([A-Z])/$1_$2/g;
        $c = uc $c;
        $self->{$c} = $config->param($p);
    };
    $set->('DnsCacheClass');
    $set->('DnsCacheArgs');
    $set->('DnsCacheArgsDeref');
    $set->('DnsCompAlias');
    $set->('DnsCompClass');
    $set->('HandlerAlias');
    $set->('HttpCompArgs');
    $set->('HttpCompClass');
    $set->('MaxHttpComp');
}

sub states
{
    my $self = shift;
    return (
        object_states => [
            $self => [
                '_start',
                '_stop',
                'create_dns_cache',
                'create_http_request',
                'create_http_comp_data',
                'dispatch_to_lightest_load',
                'dispatch_http_fetch',
                'finalize_job',
                'fake_error_response',
                'handle_signal',
                'handle_dns_response',
                'handle_http_response',
                'install_sighandlers',
                'register_http_request',
                'register_dns_request',
                'signal_http_comp',
                'spawn_dns_comp',
                'spawn_http_comp',
                'unregister_http_request',
            ]
        ]
    );
}

sub attr
{
    my $self  = shift;
    my $field = shift;

    $field =~ s/([a-z])([A-Z])/$1_$2/g;
    $field = uc $field;

    my $attr = $self->{$field};
    if (@_) {
        $self->{$field} = shift;
    }
    return $attr;
}

sub spawn
{
    my $class = shift;
    my $self  = $class->new(@_);

    POE::Session->create(
        heap => $self,
        $self->states,
    );
    return $self;
}

sub check_job_type
{
    my $self = shift;
    if (my $type = $self->strict_job_type) {
        return eval { $_[0]->isa($type) };
    }
    return 1;
}

sub _start
{
    my($kernel, $session, $obj) = @_[KERNEL, SESSION, OBJECT];

    $kernel->alias_set($obj->alias);

    # Install signal handlers
    $kernel->call($session, 'install_sighandlers');

    # Spawn a DNS component to resolve hostnames
    $kernel->call($session, 'spawn_dns_comp');

    my $cache = $kernel->call($session, 'create_dns_cache');
    $obj->attr(dns_cache => $cache);

    $kernel->call(
        $session,
        'spawn_http_comp',
        $obj->max_http_comp > 10 ? 10 : $obj->max_http_comp
    );
}

sub _stop
{
    my($kernel, $heap, $obj) = @_[KERNEL, HEAP, OBJECT];
    Xango::debug("[_stop]: broker session stopping.");

    $kernel->alias_remove($obj->alias);
}

sub spawn_dns_comp
{
    my($kernel, $object) = @_[KERNEL, OBJECT];

    my $class = $object->dns_comp_class();
    my $alias = $object->dns_comp_alias();

    eval "require $class";
    die if $@;
    $class->spawn(Alias => $alias, Timeout => 45);
}

sub spawn_http_comp
{
    my($kernel, $session, $obj, $how_many) = @_[KERNEL, SESSION, OBJECT, ARG0];

    Xango::debug("[spawn_http_comp]: Spawn $how_many HTTP components");

    my $fetchers = $obj->fetchers;
    my $class    = $obj->http_comp_class;
    my $args     = $obj->http_comp_args;

    eval "require $class";
    die if $@;
    for (1..$how_many) {
        my $alias = join('-', 'http', time(), rand());
        $class->spawn(@$args, Alias => $alias);

        $fetchers->{$alias} =
            $kernel->call($session, 'create_http_comp_data', $alias);
    }
}

sub create_http_comp_data
{
    return {};
}

sub signal_http_comp
{
    my($kernel, $http_comp) = @_[KERNEL, ARG0];
    $kernel->signal($http_comp, 'INT');
}

sub handle_signal
{
    my($kernel, $obj, $sig) = @_[KERNEL, OBJECT, ARG0];

    if ($sig eq 'PIPE') { # ignore
        return;
    }

    Xango::debug("[handle_signal]: Received signal $sig. Setting shutdown state");
    $obj->shutdown(1);
    $kernel->sig_handled();
}

sub install_sighandlers
{
    my($kernel) = @_[KERNEL];

    $kernel->sig(PIPE => 'handle_signal');
    $kernel->sig(INT  => 'handle_signal');
    $kernel->sig(QUIT => 'handle_signal');
    $kernel->sig(TERM => 'handle_signal');
    $kernel->sig(HUP  => 'reload_config');
}

sub create_dns_cache
{
    my ($kernel, $obj) = @_[KERNEL, OBJECT];

    my $class = $obj->dns_cache_class;
    my $args  = $obj->dns_cache_args;
    my $deref = $obj->dns_cache_args_deref;

    eval "require $class";
    die if $@;

    return $deref ?
        $class->new(
            ref($args) eq 'HASH'  ? %$args :
            ref($args) eq 'ARRAY' ? @$args :
            die "DnsCacheArgs could not be dereferenced to an array or hash"
        ) :
        $class->new($args);
}

sub create_http_request
{
    my($kernel, $session, $obj, $job) = @_[KERNEL, SESSION, OBJECT, ARG0];

    my $uri = $job->uri->clone;
    $uri->host($job->notes('host_ip'));
    my $req = HTTP::Request->new(GET => $uri);
    $req->header(Host => $job->notes('host_name'));

    # Give the handler a chance to munge with the request
    $kernel->call($obj->handler_alias, 'prep_request', $job, $req);

    return $req;
}

sub register_dns_request
{
    my($obj, $host, $job) = @_[OBJECT, ARG0, ARG1];

    my $queue = $obj->dns_pending();
    $queue->{$host} ||= [];
    push @{$queue->{$host}}, $job;
}

sub register_http_request
{
    my($obj, $fetcher_id, $job) = @_[OBJECT, ARG0, ARG1];

    # We need to register that there was a new request to this fetcher
    my $fetchers = $obj->fetchers();
    my $data     = $fetchers->{$fetcher_id};

    $data->{last_request_time}  = time();
    $data->{jobs}->{$job->id} = $job;
}

sub unregister_http_request
{
    my($obj, $fetcher_id, $job) = @_[OBJECT, ARG0, ARG1];

    my $fetchers = $obj->fetchers();
    my $data     = $fetchers->{$fetcher_id};

    $data->{last_request_time} = time();
    delete $data->{jobs}->{$job->id};
}

sub dispatch_to_lightest_load
{
    my($kernel, $session, $obj, $job) = @_[KERNEL, SESSION, OBJECT, ARG0];

    # Find the http component with the least load. 
    my $min = undef;
    my $fetcher_id;

    while (my($id, $data) = each %{$obj->fetchers}) {
        my $size = scalar keys %{$data->{jobs}};
        if (!defined $min || $min > $size) {
            $fetcher_id = $id;
            $min = $size;
            last unless $min;
        }
    }

    if ($fetcher_id) {
        $job->notes(fetcher => $fetcher_id);
        $kernel->call($session, 'dispatch_http_fetch', $job);
    }
}

sub dispatch_http_fetch
{
    my($kernel, $session, $obj, $job) = @_[KERNEL, SESSION, OBJECT, ARG0];

    my $uri = $job->uri;
    Xango::debug("[dispatch_http_fetch]: dispatch_http_fetch $uri");

    # Apply policy
    if (! $kernel->call($obj->handler_alias, 'apply_policy', $job)) {
        return $kernel->call($session, 'finalize_job', $job);
    }

    # Resolve this URI first (check flags for sanity. we don't want to
    # get into an infinite loop or something)
    if ($uri->host =~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
        $job->notes(host_name => $uri->host);
        $job->notes(host_ip   => $uri->host);
    } elsif (! $job->notes('dns_resolved') &&
        $uri->host !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
        my $host     = $uri->host;
        my $dnscache = $obj->dns_cache();
        my $host_ip  = $dnscache->get($host);

        if ($host_ip) {
            $job->notes(dns_resolved => 1);
        } else {
            $kernel->call($session, 'register_dns_request', $host, $job);
            return $kernel->post(
                $obj->dns_comp_alias,
                'resolve',
                'handle_dns_response',
                $host
            );
        }

        # We cache failed responses as well. Check if this is such case
        if ($host_ip eq '0.0.0.0') {
            my $err = "Could not connect to " .
                "$uri (No address associated with $host (CACHED))";
            return $kernel->yield('fake_error_response', $job, $err);
        }

        $job->notes(host_name => $host);
        $job->notes(host_ip   => $host_ip);
    }

    my $host_ip = $job->notes('host_ip');

    # At this point, either the uri that was requested was already an IP
    # address, or we have successfully resolved the hostname.
    if (! $host_ip ||
          $host_ip !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
        Xango::debug(sprintf(<<EOM, $host_ip, $uri));
[dispatch_http_fetch]:
    Sanity check failed. Expected to have a resolved host_ip, but got 
    '%s' for URI '%s'. Tossing job out.
EOM
        return $kernel->yield('finalize_job', $job);
    }

    # Create a new HTTP::Request object.
    my $request = $kernel->call($session, 'create_http_request', $job);

    my $fetcher = $job->notes('fetcher');
    # Register to the fetcher that there was a request.
    $kernel->call($session, 'register_new_request', $fetcher, $job);

    my @request_args =
        ($fetcher, 'request', 'handle_http_response', $request, $job);
    if (&Xango::DEBUG) {
        push @request_args, 'fetcher_progress';
    }

    # Fire!
    $kernel->post(@request_args) or
        die "Failed to post to fetcher ${fetcher}'s request state";
}

sub handle_http_response
{
    my($kernel, $session, $obj, $reqpack, $respack) =
        @_[KERNEL, SESSION, OBJECT, ARG0, ARG1];

    my $job = $reqpack->[1];
    my $uri = $job->uri;
    Xango::debug("[handle_http_response]: $uri");

    # Immediately unregister this request
    $kernel->call($session, 'unregister_http_request', $job->notes('fetcher'), $job);

    # put the uri back to hostname, if available
    if ($job->notes('host_name')) {
        $uri->host($job->notes('host_name'));
    }
    my $response = $respack->[0];
    my $request  = $reqpack->[0];

    $job->notes(http_response => $response);
    if ($request->uri ne $uri) { # probably DNS
        $request->uri($uri);
    }
    $response->request($request);

    $kernel->post($obj->handler_alias, 'handle_response', $job) or
        die "Failed to post event 'handle_response' to '" . $obj->handler_alias . "'";
    $kernel->yield('finalize_job', $job);
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

    my $request = HTTP::Request->new(GET => $job->uri);
    $request->content('DUMMY-REQUEST');
    $response->request($request);
    $kernel->yield('handle_http_response', [ $request, $job ], [ $response ]);
}

sub DESTROY {}
sub AUTOLOAD
{
    my $self = $_[0];

    goto UNDEFINED unless ref($self) ne 'HASH';

    my $method = uc $AUTOLOAD;
    $method =~ s/^.+::([^:]+)$/$1/;

    goto UNDEFINED unless exists $self->{$method};

    my $code = sprintf(<<'    EOSQL', $AUTOLOAD, $method, $method);
        sub %s {
            my $self = shift;
            my $ret  = $self->{%s};
            if (@_) {
                $self->{%s} = shift;
            }
            return $ret;
        }
    EOSQL

    eval $code;
    die if $@;
    goto &$AUTOLOAD;

UNDEFINED:
    Carp::croak("Undefined subroutine $AUTOLOAD");
}

sub finalize_job
{
    my($kernel, $session, $obj, $job) = @_[KERNEL, SESSION, OBJECT, ARG0];

    my $fetcher_id = $job->notes('fetcher');
    $kernel->call($obj->handler_alias, 'finalize_job', $job);
    $kernel->call($session, 'unregister_http_request', $fetcher_id, $job);
    if ($obj->undef_on_finalize) {
        undef $job;
    }
    Xango::debug("[finalize_job]: fetcher $fetcher_id done");
}

sub handle_dns_response
{
    my($kernel, $obj) = @_[KERNEL, OBJECT];

    my $request_address = $_[ARG0]->[0];
    my $response_object = $_[ARG1]->[0];
    my $response_error  = $_[ARG1]->[1];

    my $pending  = $obj->dns_pending();
    my $requests = $pending->{$request_address};
    if (!$requests) {
        Xango::debug("Resolved $request_address, but no requests associated to it were found!");
        return undef;
    }

    if (defined $response_object) {
        my $ip;
        foreach my $answer ($response_object->answer()) {
            next unless $answer->type eq 'A';
            $ip = $answer->rdatastr;
            last;
        }

        if ($ip) {
            Xango::debug("[handle_dns_response]: $request_address resolved to $ip.");
            $obj->dns_cache->set($request_address, $ip);
            foreach my $job (@$requests) {
                $kernel->yield('dispatch_http_fetch', $job);
            }
            return 1; # yay
        }
    }

    # If we got here, everything else is an error.
    # XXX - Make sure that fetcher->{dispatched} is unset
    if (!defined $response_object) {
        # No response - create a fake 500 response, short-cicuit and send
        # the result to the job processor
        foreach my $job (@$requests) {
# XXX - Rethink what this does.
#            delete $heap->{FETCHERS}->{$job->{fetcher}}->{dispatched}->{$job->{id}};
            $kernel->yield(
                'fake_error_response',
                $job,
                "Could not connect to " . $job->uri . " ($response_error)"
            );
        }
    } else {
        # If we got here, we probably didn't find any 'A' records in the
        # DNS lookup. Treat this as an error as well
        foreach my $job (@$requests) {
# XXX - Rethink what this does.
#            delete $heap->{FETCHERS}->{$job->{fetcher}}->{dispatched}->{$job->{id}};
            $kernel->yield(
                'fake_error_response',
                $job,
                "Could not connect to " . $job->uri . " ($response_error)"
            );
        }
    }
    my $dnscache = $obj->dns_cache;
    $dnscache->set($request_address, '0.0.0.0');
    return undef;
}

1;

__END__

=head1 NAME

Xango::Broker::Base - Base Class for Xango Broker

=head1 SYNOPSIS

  package MyBroker;
  use strict;
  use base qw(Xango::Broker::Base);

=head1 DESCRIPTION

Xango::Broker::Base implements the common broker methods.

You should be using Xango::Broker::Pull or Xango::Broker::Push in your 
applications. See respective documentations.

=head1 OBJECT METHODS

=head2 spawn(%args)

Create a new Xango::Broker::Base object, and also spawn a new POE::Session
using that new object. To start a Xango::Broker session, you should be using
spawn(), and not new().

Accepts the same arguments as new().

=head2 new(%args)

Create a new Xango::Broker::Base object. Arguments passed to it are
stored via initialize()

=over 4

=item Alias (scalar)

The POE session alias for the broker.

=item ConfigFile (scalar)

Path to the config file used by Xango::Config. Values in this file will be 
used as the default value for other variables. 

=item DnsCacheClass (scalar)

Perl class to use for DNS cache.

=item DnsCacheArgs (hashref | arrayref)

Arguments to the DNS cache constructor

=item DnsCacheArgsDeref (boolean)

Try to de-reference the DNS cache constructor argument specified by
DnsCacheArgs when creating the cache. This is required if your DNS cache class
uses simple list values instead of hash/array refs (e.g. Cache::Cache and
Cache::FastMmap)

=item DnsCompClass (scalar)

Specify the POE component class to asynchronously resolve DNS requests.
By default POE::Component::Client::DNS is used.

=item HandlerAlias (scalar)

The POE session alias for the handler.

=item HttpCompClass (scalar)

Specify the POE component class to handle the actual HTTP fetching.
By default POE::Component::Client::HTTP is used.

=item HttpCompArgs (hashref | arrayref)

Arguments to the HTTP fetching component constructor.

=item MaxHttpComp (integer)

The number of concurrent http agents (i.e. the number of
POE::Component::Client::HTTP sessions) that are allowed. The default is 10,
but for anything other than a toy application, something in the order of
50 ~ 100 is the recommended value.

Unless this number is less than 10, the broker starts with 10 sessions,
and successively grows the pool of agents when there are not enough
agents to handle the currently available jobs, until the maximum is reached.

If the max is less than 10, the starting number if equal to the max.

=back

=head2 initialize

Initializes the broker object.

=head2 attr(key =E<gt> $value)

General purpose getter/stter for attributes.

=head2 dns_comp_class

The class name for DNS resolver component.

=head2 dns_comp_alias

The alias for DNS resolver component.

=head2 states

Returns the states list as passed to the POE::Session constructor.

=head1 STATES

States are all called either by yield() or post(). The arguments described
below are to be used in that context, i.e. yield('state', $arg1, $arg2...)

=head2 check_job_type

=head2 create_dns_cache

Creates and sets the DNS cache. You probably don't need to worry about this.

=head2 create_http_comp_data

=head2 create_http_request

Creates a new HTTP::Request object to be fetched.

=head2 dispatch_http_fetch($job)

Start an HTTP fetch for $job. $job must have a HTTP fetcher associated to it.

=head2 dispatch_to_lightest_load($job)

Choose the HTTP fetcher session with the least load, and call 
dispath_http_fetch after associating it to a job

=head2 fake_error_response

Create a fake HTTP error response, which is passed to handle_http_response.
This is used to notify internal errors to the handler.

=head2 install_sighandlers

Installs the global signal handlers.

=head2 spawn_dns_comp

Spawns the component to resolve DNS lookups.

=head2 spawn_http_comp($howmany)

=head2 signal_http_comp

Send a signal to the specified HTTP component.

=head2 handle_dns_response

=head2 handle_http_response

=head2 handle_signal

Handle a given signal. The signal name is in ARG0.

=head2 register_dns_request

=head2 register_http_request

=head2 unregister_http_request

=head2 finalize_job

=head1 SEE ALSO

L<Xango::Broker::Pull> L<Xango::Broker::Push>

=head1 AUTHOR

Copyright (c) 2005 Daisuke Maki E<lt>dmaki@cpan.orgE<gt>. All rights reserved.
Development funded by Brazil, Ltd. E<lt>http://b.razil.jpE<gt>

=cut 
