# $Id: Config.pm 92 2005-10-17 17:25:36Z daisuke $
#
# Copyright (c) 2005 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package Xango::Config;
use strict;

# XXX - While YAML rocks (it really does), this may be one of
# those modules that we need to shed to reduce memory footprint.
# See if we need to strip out memory later
# XXX - also, see if we can come up with a config loader of sorts.
use YAML();

my $instance;

sub import
{
    my $class = shift;
    if(@_) {
        $class->init(@_);
    }
}

sub init
{
    my($class, $filename, $opts) = @_;
    if (ref ($opts) ne 'HASH') {
        $opts = {};
    }

    if ($opts->{force_reload}) {
        $instance = bless YAML::LoadFile($filename), $class;
    } else {
        $instance ||= bless YAML::LoadFile($filename), $class;
    }
    $instance;
}

sub instance { return $instance }

sub param
{
    my $self = ref($_[0]) ? shift : shift->instance;
    my $name = shift;
    my $value = $self->{$name};
    if (@_) {
        $self->{$name} = shift;
    }
    return ref($value) =~ /^(?:ARRAY|HASH)$/ && wantarray ? @$value : $value;
}

1;

__END__

=head1 NAME

Xango::Config - Global Xango Config

=head1 SYNOPSIS

  use Xango::Config;
  Xango::Config->init($filename);
  # or 
  use Xango::Config ($filename);

  # elsewhere in the code...
  my $config = Xango::Config->instance();

=head1 DESCRIPTION

Xango::Config is a singleton object that contains all configuration variables
for Xango system. It's a singleton that reads input files from a YAML file.

All the variables specified in the file is available from the param() method
as Perl data structures.

=head1 METHODS

=head2 init($filename[, \%opts])

=over 4

Class method that initializes the config with the contents in the YAML file. 
Once initialized, subsequent calls to init() has no effect unless 
I<force_reload> is specified in the options hash:

  Xango::Config->init($file, { force_reload => 1 });

=back

=head2 instance()

=over 4

Returns the current instance of Xango::Config. will return undef unless you
have initialized the instance by calling init().

=back

=head2 param($name[, $value])

=over 4

Get/Set the value of a config variable. Returns whatever Perl structure that
you have specified in the config file.

Since Xango::Config is an You may use param() as both a class method or an instance method

=back

=head1 AUTHOR

Copyright (c) 2005 Daisuke Maki E<lt>dmaki@cpan.orgE<gt>
Development funded by Brazil, Ltd. E<lt>http://b.razil.jpE<gt>

=cut
