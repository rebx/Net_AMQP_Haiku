package Net::AMQP::Haiku::Properties;
use strict;
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(
    def_queue_properties def_publish_properties def_queue_bind_properties
    def_consume_properties def_publish_header_properties
);

use Net::AMQP::Haiku::Constants;

sub def_queue_properties {
    return {
        auto_delete => FLAG_AUTO_DELETE,
        no_ack      => FLAG_NO_ACK,
        nowait      => FLAG_NO_WAIT,
        durable     => FLAG_DURABLE,
        queue       => DEFAULT_QUEUE,
        passive     => FLAG_PASSIVE,
        ticket      => DEFAULT_TICKET,
        exclusive   => FLAG_EXCLUSIVE,
    };
}

sub def_publish_properties {
    return {
        routing_key => DEFAULT_QUEUE,
        exchange    => DEFAULT_EXCHANGE,
        mandatory   => FLAG_MANDATORY,
        immediate   => FLAG_IMMEDIATE,
        ticket      => DEFAULT_TICKET,
    };
}

sub def_publish_header_properties {
    return {
        reply_to       => DEFAULT_QUEUE,
        correlation_id => DEFAULT_CORRELATION_ID,
    };
}

sub def_queue_bind_properties {
    return {
        ticket      => DEFAULT_TICKET,
        queue       => DEFAULT_QUEUE,
        exchange    => DEFAULT_EXCHANGE,
        routing_key => DEFAULT_QUEUE,
        nowait      => FLAG_NO_WAIT,
    };
}

sub def_consume_properties {
    return {
        ticket       => DEFAULT_TICKET,
        queue        => DEFAULT_QUEUE,
        consumer_tag => DEFAULT_CONSUMER_TAG,
        no_local     => FLAG_NO_LOCAL,
        no_ack       => FLAG_NO_ACK,
        exclusive    => FLAG_EXCLUSIVE,
        nowait       => FLAG_NO_WAIT,
    };
}

1;
