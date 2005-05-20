# $Id: Config.pm 43 2005-04-05 14:55:44Z daisuke $
#
# Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package Xango::Config;
use strict;

# XXX - While YAML rocks (it really does), this may be one of
# those modules that we need to shed to reduce memory footprint.
# See if we need to strip out memory later
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
    my($class, $filename) = @_;
    $instance ||= bless YAML::LoadFile($filename), $class;
    undef;
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

=head2 init($filename)

Class method that initializes the config with the contents in the YAML file. 
Once initialized, subsequent calls to init() has no effect.

=head2 instance()

Returns the current instance of Xango::Config. will return undef unless you
have initialized the instance by calling init().

=head2 param($name[, $value])

Get/Set the value of a config variable. Returns whatever Perl structure that
you have specified in the config file.

Since Xango::Config is an You may use param() as both a class method or an instance method

=head1 CONFIGURATION VARIABLES

=head1 AUTHOR

Daisuke Maki E<lt>dmaki@cpan.orgE<gt>
Development funded by Brazil, Ltd. E<lt>http://b.razil.jpE<gt>

=cut
