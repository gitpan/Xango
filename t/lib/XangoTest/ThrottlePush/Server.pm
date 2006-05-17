package XangoTest::ThrottlePush::Server;
use strict;
use base qw(HTTP::Server::Simple::CGI);
use IO::Socket;

sub new
{
    my $class = shift;
    my $port = 8000;
    
    while (1) {
        my $sock = IO::Socket::INET->new(
            Listen => 1,
            LocalPort => $port,
            Proto => 'tcp'
        );
        if ($sock) {
            $sock->close;
            last;
        }

        $port++;
    }

    $class->SUPER::new($port);
}

sub handle_request
{
    print "HTTP 400 Connection Refused\r\n\r\n";
}

1;