# $Id: Broker.pm 92 2005-10-17 17:25:36Z daisuke $
#
# Copyright (c) 2005 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package Xango::Broker;
use strict;

# usage of this class is now depreated. if loaded, it will simply
# load Xango::Broker::Pull, which was the default behavior in
# version < 1.00
use base qw(Xango::Broker::Pull);

warn "Xango::Broker is deprecated. Please use Xango::Broker::Pull instead";

1;

__END__

=head1 NAME

Xango::Broker - Broker HTTP Requests (Deprecated)

=head1 SYNOPSIS

  use Xango::Broker;
  use MyHandler;
  MyHandler->spawn();
  Xango::Broker->spawn();
  POE::Kernel->run();

  # or,
  xango -h MyHandler

=head1 DESCRIPTION

As of 1.00 (and 0.99), use of Xango::Broker is deprecated. Use 
Xango::Broker::Pull instead.

For compatiblity, using Xango::Broker is now equivalent to using Xango::Broker::Pull.

=head1 AUTHOR

Copyright (c) 2005 Daisuke Maki E<lt>dmaki@cpan.orgE<gt>. All rights reserved.
Development funded by Brazil, Ltd. E<lt>http://b.razil.jpE<gt>

=cut 
