package Net::AMQP::Haiku::Helpers;

use strict;
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(deserialize serialize make_get_header def_queue_properties
    def_publish_properties);

use Net::AMQP;
use Net::AMQP::Protocol::v0_8;
use Net::AMQP::Haiku::Constants;

sub deserialize {
    my ($data) = @_;
    return unless $data;

    return Net::AMQP->parse_raw_frames( \$data );
}

sub serialize {
    my ( $raw_msg, $user_name, $cust_pub_args, $header_args ) = @_;

    return unless ( $raw_msg && $user_name );

    my $pub_args = def_publish_properties();
    if ( defined($cust_pub_args)
        and UNIVERSAL::isa( $cust_pub_args, 'HASH' ) )
    {
        $pub_args = { %{$pub_args}, %{$cust_pub_args} };
    }

    my $pub_frame = Net::AMQP::Protocol::Basic::Publish->new( %{$pub_args} )
        or return;

    my $frame_hdr = Net::AMQP::Frame::Header->new(
        weight => $header_args->{weight} || DEFAULT_PUBLISH_WEIGHT,
        body_size    => length($raw_msg),
        header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
            content_type     => 'application/octet-stream',
            content_encoding => '',
            headers          => {},
            delivery_mode    => FLAG_DELIVERY,
            priority         => FLAG_PRIORITY,
            correlation_id   => DEFAULT_CORRELATION_ID,
            expiration       => undef,
            message_id       => undef,
            timestamp        => time,
            type             => undef,
            user_id          => $user_name,
            app_id           => undef,
            cluster_id       => undef, ), ) or return;

    my $frame_body = Net::AMQP::Frame::Body->new( payload => $raw_msg )
        or return;
    $pub_frame = $pub_frame->frame_wrap();

    return ( $pub_frame, $frame_hdr, $frame_body );
}

sub make_get_header {
    my ( $queue, $ticket, $extra_args ) = @_;

    return unless $queue;
    $ticket ||= DEFAULT_TICKET;
    $extra_args ||= {};

    # in a synchronous world
    return Net::AMQP::Protocol::Basic::Get->new(
        no_ack => FLAG_NO_ACK,
        queue  => $queue,
        ticket => $ticket,
        %{$extra_args}, );
}

sub def_queue_properties {

    return {
        ticket       => DEFAULT_TICKET,
        exclusive    => 0,
        queue        => DEFAULT_QUEUE,
        consumer_tag => DEFAULT_CONSUMER_TAG,
        passive      => 0,
        durable      => 0,
        auto_delete  => 0,
        no_ack       => 1,
        nowait       => 0,
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

1;
