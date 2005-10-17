# $Id: BaseHandler.pm 89 2005-10-17 13:25:54Z daisuke $
#
# Copyright (c) 2005 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package XangoTest::BaseHandler;
use strict;
use POE;
our $AUTOLOAD;

sub new
{
    my $class = shift;

    my $self  = bless {
        ALIAS           => 'handler',
    }, $class;
    $self->initialize(@_);
    return $self;
}

sub initialize
{
    my $self = shift;
    my %args = @_;

    my $k_munge;
    foreach my $k (keys %args) {
        $k_munge = $k;
        $k_munge =~ s/([a-z])([A-Z])/$1_$2/g;
        $self->{uc ($k_munge)} = $args{$k};
    }
}

sub spawn
{
    my $class = shift;
    my $self  = $class->new(@_);

    POE::Session->create(
        $self->states,
    );

    return $self;
}

sub states
{
    my $self = shift;
    return (
        object_states => [
            $self => [ qw(_start _stop handle_response apply_policy) ]
        ]
    );
}

sub _start { $_[KERNEL]->alias_set($_[OBJECT]->alias) }
sub _stop  { $_[KERNEL]->alias_remove($_[OBJECT]->alias) }
sub handle_response {}
sub apply_policy { 1 }

sub AUTOLOAD
{
    my $self = $_[0];
    goto UNDEFINED unless ref($self) ne 'HASH';

    my $method = uc $AUTOLOAD;
    $method =~ s/^.+::([^:]+)$/$1/;

    goto UNDEFINED unless exists $self->{$method};

    eval sprintf(<<'    EOSQL', $AUTOLOAD, $method, $method);
        sub %s {
            my $self = shift;
            my $ret  = $self->{$method};
            if (@_) {
                $self->{$method} = shift;
            }
            return $ret;
        }
    EOSQL

    die if $@;
    goto &$AUTOLOAD;

UNDEFINED:
    Carp::croak("Undefined subroutine $AUTOLOAD");
}

1;
