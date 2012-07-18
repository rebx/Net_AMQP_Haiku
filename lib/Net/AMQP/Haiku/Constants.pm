package Net::AMQP::Haiku::Constants;

use strict;
use warnings;
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(
    DEFAULT_HOST DEFAULT_PORT DEFAULT_PROTO DEFAULT_TIMEOUT
    DEFAULT_LOCALE DEFAULT_AUTH_MECHANISM
    DEFAULT_USERNAME DEFAULT_PASSWORD
    DEFAULT_VHOST DEFAULT_QUEUE DEFAULT_CHANNEL HANDSHAKE_CHANNEL
    CLIENT_PLATFORM FLAG_DEBUG
    SEND_RETRY RECV_RETRY DEFAULT_RECV_LEN
    _FOOTER_OCT _FOOTER_LENGTH _HEADER_LENGTH
    DEFAULT_TICKET  DEFAULT_EXCHANGE_NAME DEFAULT_EXCHANGE_TYPE
    DEFAULT_PUBLISH_WEIGHT FLAG_MANDATORY FLAG_IMMEDIATE FLAG_NO_ACK
    DEFAULT_CORRELATION_ID DEFAULT_CONSUMER_TAG FLAG_DELIVERY FLAG_PRIORITY
    FLAG_AUTO_DELETE FLAG_DURABLE FLAG_NO_WAIT FLAG_EXCLUSIVE FLAG_PASSIVE
    @PUBLISH_FRAME_ATTRS @HEADER_FRAME_ATTRS FLAG_NO_LOCAL FLAG_INTERNAL
    FLAG_IF_UNUSED FLAG_IF_EMPTY
    DEFAULT_QOS_FLAG_GLOBAL DEFAULT_QOS_SIZE DEFAULT_QOS_COUNT
    $AUTH_MECHANISM_LIST $EXCHANGE_TYPES
);

### CONSTANTS ###

# SERVER stuff
use constant DEFAULT_HOST           => '127.0.0.1';
use constant DEFAULT_PORT           => 5672;
use constant DEFAULT_PROTO          => 'tcp';
use constant DEFAULT_TIMEOUT        => 60;
use constant DEFAULT_LOCALE         => 'en_US';
use constant DEFAULT_AUTH_MECHANISM => 'AMQPLAIN';
use constant DEFAULT_USERNAME       => 'guest';
use constant DEFAULT_PASSWORD       => 'guest';
use constant DEFAULT_VHOST          => '/';
use constant DEFAULT_QUEUE          => '';
use constant DEFAULT_CHANNEL        => 1;
use constant HANDSHAKE_CHANNEL      => 0;

# Local to module
use constant CLIENT_PLATFORM  => 'Perl';
use constant FLAG_DEBUG       => 0;
use constant SEND_RETRY       => 3;
use constant RECV_RETRY       => 5;
use constant DEFAULT_RECV_LEN => 1024;     # receive length

# AMQP frame stuff
use constant _FOOTER_OCT    => 206;
use constant _FOOTER_LENGTH => 1;
use constant _HEADER_LENGTH => 7;

# FRAME stuff
use constant DEFAULT_TICKET        => 0;          # ticket access
use constant DEFAULT_EXCHANGE_TYPE => 'direct';
use constant DEFAULT_EXCHANGE_NAME =>
    '';    # the name of the exchange you want to use
use constant DEFAULT_PUBLISH_WEIGHT => 0;    # frame weight
use constant FLAG_MANDATORY         => 0;    # mandatory routing
use constant FLAG_IMMEDIATE         => 0
    ; # for flagging immediate delivery. if set to 1, it will guarantee that the message can be consumed.
use constant FLAG_DELIVERY => 1;    # for flagging delivery
use constant FLAG_PRIORITY => 1;    # Basic::ContentHeader priority flag
use constant FLAG_PASSIVE  => 0
    ; # Exchange::Declare passive flag. If set, it will instruct the server not to create the exchange
use constant FLAG_NO_ACK    => 1;    # frame ack
use constant FLAG_EXCLUSIVE => 0;    # request exclusive consumer access
use constant FLAG_DURABLE =>
    0;    # set queue as durable. Let the mnesia db bring it back on reboot
use constant FLAG_NO_WAIT     => 0; # tells the server not to reply to method
use constant FLAG_NO_LOCAL    => 0; # no_local flag
use constant FLAG_IF_UNUSED   => 1; # flag for deleting a queue if it's unused
use constant FLAG_IF_EMPTY    => 1; # flag for deleting a queue if it's empty
use constant FLAG_AUTO_DELETE => 0; # automaticaly delete the message
use constant DEFAULT_CONSUMER_TAG    => '';     # default consumer tag
use constant DEFAULT_CORRELATION_ID  => '1';    #
use constant FLAG_INTERNAL           => 0;
use constant DEFAULT_QOS_SIZE        => 0;
use constant DEFAULT_QOS_COUNT       => 1;
use constant DEFAULT_QOS_FLAG_GLOBAL => 0;
### CONSTANTS ###

# frame attributes
our @PUBLISH_FRAME_ATTRS
    = qw(immediate routing_key mandatory ticket exchange);
our @HEADER_FRAME_ATTRS = qw(reply_to correlation_id);

# known auth mechanisms
our $AUTH_MECHANISM_LIST = {
    'PLAIN'          => 1,
    'AMQPLAIN'       => 1,
    'RABBIT-CR-DEMO' => 1,
};

our $EXCHANGE_TYPES = {
    'direct' => 1,
    'fanout' => 1,
    'topic'  => 1,
};

1;
