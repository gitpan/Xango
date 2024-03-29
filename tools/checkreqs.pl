# $Id$
#
# Copyright (c) 2006 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

use strict;

my $interactive = 
  -t STDIN && (-t STDOUT || !(-f STDOUT || -c STDOUT)) ;   # Pipe?

my %requires = (
    'Cache::Cache'   => 0,
    'Data::Average'  => '>= 0.02',
    'HTTP::Request'  => 0,
    'HTTP::Response' => 0,
    'Log::Dispatch'  => 0,
    'POE'            => 0,
    'YAML'           => 0, # See Xango::Config
);

my $check_installed = 
    $Module::Build::VERSION ?
        sub { Module::Build->check_installed_status(@_) } :
        sub {
            my $module  = shift;
            my $version = shift;
            eval "require $module";
            return $@ ? 0 : 
                do { no strict; return ${"${module}::VERSION"} } >= $version;
        }
;
my $prompt = 
    $Module::Build::VERSION ?
        sub { Module::Build->y_n(@_) } :
        sub {
            my $message = shift;
            my $default = shift || '';
            print $message;
            print "[$default] ";

            my $value = $interactive ? <STDIN> : '';
            chomp;
            $value ||= $default;
            return $value;
        }
;

my @ask;
my @optional = (
    qw(POE::Component::Client::DNS POE::Component::Client::HTTP),
);
foreach my $module(@optional) {
    my $r = $check_installed->($module, 0);
    next if $r->{ok};

    print "* $module not installed\n";
    push @ask, $module;
}

if (@ask) {
    print <<EOM;

Xango by default uses the following missing modules. If you know what you
are doing (and/or plan to customize the modules that are going to be used),
then you do not need to install them.

EOM
    foreach my $module (@ask) {
        my $require_mod = $prompt->("Install $module?", 'y');
        if ($require_mod) {
            $requires{$module} = 0;
        }
    }
}

return %requires;
