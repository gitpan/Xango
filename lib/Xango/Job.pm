# $Id: Job.pm 88 2005-10-17 09:05:04Z daisuke $
#
# Copyright (c) 2005 Daisuke Maki <dmaki@cpan.org>
# All rights reserved.

package Xango::Job;
use strict;

sub new
{
    my $class = shift;
    my %args  = @_;

    my $self  = bless {notes => {}}, $class;

    $self->id(delete $args{id});
    $self->uri(delete $args{uri});
    while (my($k, $v) = each %args) {
        $self->notes($k, $v);
    }

    return $self;
}

sub _elem
{
    my $self  = shift;
    my $field = shift;
    my $ret   = $self->{$field};
    if (@_) { $self->{$field} = shift }
    if (wantarray) {
        (ref($ret) eq 'ARRAY') ? @$ret : 
        (ref($ret) eq 'HASH')  ? %$ret :
        $ret;
    } else {
        return $ret;
    }
}

sub id  { shift->_elem('id', @_) }
sub uri { shift->_elem('uri', @_) }
sub _notes { shift->_elem('notes', @_) }
sub notes
{
    my $self  = shift;
    my $field = shift;
    my $notes = $self->_notes();

    my $ret = $notes->{$field};
    if (@_) { $notes->{$field} = shift }

    if (wantarray) {
        (ref($ret) eq 'ARRAY') ? @$ret : 
        (ref($ret) eq 'HASH')  ? %$ret :
        $ret;
    } else {
        return $ret;
    }
}

1;

__END__

=head1 NAME

Xango::Job - Xango Job

=head1 SYNOPSIS

  use Xango::Job;
  my $job = Xango::Job->new(uri => $uri, foo => $foo, bar => $bar);

=head1 DESCRIPTION

For backwards compatibility (and a little bit for flexibility), all 'job'
instances should be a hashref. But it's up to you to define what a job is.

Newer modules should be using the notes() function to store arbitrary data.

=head1 METHODS

=head2 new(uri =E<gt> $uri, [key =E<gt> $value, key =E<gt> $value, ...])

Create a new Xango::Job object.

=head1 AUTHOR

Copyright 2005 Daisuke Maki E<lt>dmaki@cpan.orgE<gt>. All rights reserved.
Development funded by Brazil, Ltd. E<lt>http://b.razil.jpE<gt>

=cut