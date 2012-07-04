package Net::AMQP::Haiku::Constants;
use strict;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(DEFAULT_HOST DEFAULT_PROTO DEFAULT_PORT DEFAULT_VHOST
    HANDSHAKE_CHANNEL DEFAULT_CHANNEL DEFAULT_QUEUE
    MAX_FRAME_LEN DEFAULT_USERNAME DEFAULT_PASSWORD FLAG_DEBUG
    DEFAULT_AUTH_MECHANISM $AUTH_MECHANISM_LIST CLIENT_PLATFORM
    DEFAULT_RECV_LEN SEND_RETRY RECV_RETRY DEFAULT_TIMEOUT DEFAULT_EXCHANGE
    _FOOTER_OCT _FOOTER_LENGTH _HEADER_LENGTH DEFAULT_TICKET
    DEFAULT_PUBLISH_WEIGHT FLAG_MANDATORY FLAG_IMMEDIATE FLAG_NO_ACK
    DEFAULT_CORRELATION_ID DEFAULT_CONSUMER_TAG FLAG_DELIVERY FLAG_PRIORITY
    DEFAULT_LOCALE);

use constant DEFAULT_HOST           => '127.0.0.1';
use constant DEFAULT_PORT           => 5672;
use constant DEFAULT_PROTO          => 'tcp';
use constant DEFAULT_VHOST          => '/';
use constant DEFAULT_QUEUE          => '';
use constant DEFAULT_CHANNEL        => 1;
use constant HANDSHAKE_CHANNEL      => 0;
use constant DEFAULT_TICKET         => 0;
use constant DEFAULT_EXCHANGE       => '';
use constant DEFAULT_PUBLISH_WEIGHT => 0;
use constant FLAG_MANDATORY         => 0;
use constant FLAG_IMMEDIATE         => 0;
use constant FLAG_DELIVERY          => 1;
use constant FLAG_PRIORITY          => 1;
use constant FLAG_NO_ACK            => 1;
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
use constant _FOOTER_OCT            => 206;
use constant _FOOTER_LENGTH         => 1;
use constant _HEADER_LENGTH         => 7;
our $AUTH_MECHANISM_LIST            => {
    'PLAIN'          => 1,
    'AMQPLAIN'       => 1,
    'RABBIT-CR-DEMO' => 1,
};
use constant DEFAULT_AUTH_MECHANISM => 'AMQPLAIN';
use constant CLIENT_PLATFORM        => 'Perl';

1;
