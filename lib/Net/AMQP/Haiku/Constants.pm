package Net::AMQP::Haiku::Constants;
use strict;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(DEFAULT_HOST DEFAULT_PROTO DEFAULT_PORT DEFAULT_VHOST
    MAX_FRAME_LEN DEFAULT_USERNAME DEFAULT_PASSWORD FLAG_DEBUG DEFAULT_QUEUE
    DEFAULT_AUTH_MECHANISM $AUTH_MECHANISM_LIST CLIENT_PLATFORM
    DEFAULT_RECV_LEN SEND_RETRY RECV_RETRY DEFAULT_TIMEOUT
    DEFAULT_CORRELATION_ID _HEADER_LENGTH DEFAULT_CONSUMER_TAG DEFAULT_LOCALE);

use constant DEFAULT_HOST           => '127.0.0.1';
use constant DEFAULT_PORT           => 5672;
use constant DEFAULT_PROTO          => 'tcp';
use constant DEFAULT_VHOST          => '/';
use constant DEFAULT_QUEUE          => '';
use constant DEFAULT_CONSUMER_TAG   => '';
use constant DEFAULT_LOCALE         => 'en_US';
use constant MAX_FRAME_LEN          => 131072;
use constant DEFAULT_USERNAME       => 'guest';
use constant DEFAULT_PASSWORD       => 'guest';
use constant DEFAULT_TIMEOUT        => 60;
use constant DEFAULT_CORRELATION_ID => 7275;
use constant FLAG_DEBUG             => 0;
use constant SEND_RETRY             => 3;
use constant RECV_RETRY             => 5;
use constant DEFAULT_RECV_LEN       => 1024;
use constant _HEADER_LENGTH         => 7;
our $AUTH_MECHANISM_LIST            => {
    'PLAIN'          => 1,
    'AMQPLAIN'       => 1,
    'RABBIT-CR-DEMO' => 1
};
use constant DEFAULT_AUTH_MECHANISM => 'AMQPLAIN';
use constant CLIENT_PLATFORM        => 'Perl';

1;
