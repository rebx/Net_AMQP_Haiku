package Net::AMQP::Haiku::Properties;

use strict;
use warnings;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(
    def_queue_properties def_publish_properties
    def_queue_bind_properties def_exchange_properties
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
        exchange    => DEFAULT_EXCHANGE_NAME,
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
        exchange    => DEFAULT_EXCHANGE_NAME,
        routing_key => DEFAULT_QUEUE,
        nowait      => FLAG_NO_WAIT,
    };
}

sub def_exchange_properties {
    return {
        ticket      => DEFAULT_TICKET,
        exchange    => DEFAULT_EXCHANGE_NAME,
        type        => DEFAULT_EXCHANGE_TYPE,
        passive     => FLAG_PASSIVE,
        durable     => FLAG_DURABLE,
        auto_delete => FLAG_AUTO_DELETE,
        internal    => FLAG_INTERNAL,
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

sub def_queue_delete_properties {
    return {
        ticket    => DEFAULT_TICKET,
        if_unused => FLAG_IF_UNUSED,
        if_empty  => FLAG_IF_EMPTY,
        nowait    => FLAG_NO_WAIT,
    };
}

sub def_queue_purge_properties {
    return {
        ticket => DEFAULT_TICKET,
        queue  => DEFAULT_QUEUE,
        nowait => FLAG_NO_WAIT,
    };
}

1;
