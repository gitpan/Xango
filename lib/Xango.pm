# $Id: Xango.pm 100 2006-04-01 01:47:55Z daisuke $
#
# Copyright (c) 2005 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package Xango;
use strict;
use vars qw($VERSION $LOGDISPATCH);
use IO::Handle;
use Log::Dispatch;
use Log::Dispatch::Handle;
use POSIX();

BEGIN
{
    $VERSION = '1.03';

    my $default_from_env = sub {
        my($var, $default) = @_;
        my $env_var = 'XANGO_' . $var;
        return exists $ENV{$env_var} ? $ENV{$env_var} : $default;
    };
    # Define symbols. If users define them before Xango.pm is loaded,
    # then we respect their values.
    my %constants = map { ($_ => $default_from_env->($_, 0)) } qw(DEBUG);

    while (my($const, $value) = each %constants) {
        if (! __PACKAGE__->can($const)) {
            eval "sub $const { '$value' }";
            die if $@;
        }
    }

    if (!$LOGDISPATCH) {
        $LOGDISPATCH = Log::Dispatch->new(callbacks => \&_format4logdispatch);
        if (&DEBUG) {
            my $io     = IO::Handle->new();
            my $dup    = $io->fdopen(fileno(STDERR), "w");
            $dup->autoflush(1);
            my $handle = Log::Dispatch::Handle->new(
                name      => 'xgDEBUG',
                min_level => 'debug',
                handle    => $dup,
            );
            $LOGDISPATCH->add($handle);
        }
    }
}

sub info
{
    if ($LOGDISPATCH) {
        $LOGDISPATCH->log(level => 'info', message => "@_");
    }
}

sub debug
{
    if(DEBUG && $LOGDISPATCH) {
        $LOGDISPATCH->log_to(level => 'debug', name => 'xgDEBUG', message => "@_");
    }
}

sub _format4logdispatch
{
    my %args    = @_;
    my $message = $args{message};
    $message =~ s/\n$//;
    return
        join('', POSIX::strftime("%Y%m%d%H%M%S ", localtime), $message, "\n");
}


1;

__END__

=head1 NAME

Xango - Event Based High Performance Web Crawler Framework

=head1 SYNOPSIS

  use Xango;

=head1 DESCRIPTION

  ******************  WARNING! WARNING! WARNING! ****************
  * This new release is NOT compatible with the old Xango 0.0x! *
  * Beware and use at your own risk.                            *
  ***************************************************************

Xango is a framework for writing web crawlers. As such, it doesn't do
a whole lot by itself - you need to create custom handlers to do the
grunt work. See the documentation for L<Xango::Manual::Intro|Xango::Manual::Intro>
for more details on how to write your own crawler.

Please note that Xango is still in beta. Some behavior may change as we
keep on developing it.

=head1 COMPONENTS

The main component that comes with Xango is the Broker component.
The Broker handles the basic flow of a web crawler - it accepts data
to fetch, applies some policies to it, fetches it, and then sends it 
for final processing. 

The only concrete implementation provided by the Broker of the above flow 
is the part where the requested URI is fetched. You must provide the rest
of the logic. See L<Xango::Broker|Xango::Broker> for details

The Handler is the component in which the Broker delegates the above
processing to.

=head1 CONSTANTS

There are a few constants that may change the behavior of Xango. You can
either set these by pre-declaring the constant subroutine of the same name
or you can set them by populating the corresponding environment variable,
which is prefixed with 'XANGO_'

For example,

  BEGIN { sub Xango::DEBUG { 1 } }
  use Xango;

or 

  $ENV{XANGO_DEBUG} = 1;
  use Xango;

will both toggle the DEBUG switch.

See blow for the list of possible flags and switches.

=head2 DEBUG

Set this to 1 if you want to enable debugging messages. 

=head1 FUNCTIONS

=head2 debug

=head2 info

These are simple interface to the underlying logging mechanism

=head1 DEBUGGING

To turn debugging on, you need to pre-declare some constants (which, in Perl,
are subroutines). For example, to turn debugging on, you need to say something
like this:

  sub Xango::DEBUG { 1 }
  use Xango;

Xango will recognize that the DEBUG flag is already set, and turn debugging on.

=head1 BUGS

Plenty, I'm sure. 
Please report bugs to RT http://rt.cpan.org/NoAuth/Bugs.html?Dist=Xango

=head1 TODO

=over 4

=item Documentation. 

Documentation for this distribution is half-baked at best. It needs a lot of
work, including a tutorial.

=back

=head1 CAVEATS

This is an alpha version release. Expect a lot of things to be still either
in broken or experimental stage.

=head1 SEE ALSO

L<POE|POE>
L<Xango::Manual::Intro>
L<Xango::Broker::Pull>
L<Xango::Broker::Push>

=head1 AUTHOR

Copyright 2005 Daisuke Maki E<lt>dmaki@cpan.orgE<gt>. All rights reserved.
Development funded by Brazil, Ltd. E<lt>http://b.razil.jpE<gt>

=cut