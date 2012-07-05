package Net::AMQP::Haiku::Helpers;

use strict;
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(deserialize serialize make_get_header def_queue_properties
    def_publish_properties);
use Data::Dumper qw(Dumper);
use Net::AMQP;
use Net::AMQP::Haiku::Constants;

sub deserialize {
    my ($data) = @_;
    return unless $data;
    return Net::AMQP->parse_raw_frames( \$data );
}

sub serialize {
    my ( $raw_msg, $user_name, $custom_args ) = @_;

    return unless ( $raw_msg && $user_name );

    my $pub_args       = def_publish_properties();
    my $header_args    = def_publish_header_properties();
    my $default_weight = $custom_args->{weight} || DEFAULT_PUBLISH_WEIGHT;
    if ( defined($custom_args)
        and UNIVERSAL::isa( $custom_args, 'HASH' ) )
    {
        map {
            $pub_args->{$_} = $custom_args->{$_}
                if ( exists( $custom_args->{$_} ) )
        } @PUBLISH_FRAME_ATTRS;
        map {
            $header_args->{$_} = $custom_args->{$_}
                if ( exists( $custom_args->{$_} ) )
        } @HEADER_FRAME_ATTRS;
    }

    my $pub_frame = Net::AMQP::Protocol::Basic::Publish->new( %{$pub_args} )
        or return;

    my $frame_hdr = Net::AMQP::Frame::Header->new(
        weight       => $default_weight,
        body_size    => length($raw_msg),
        header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
            content_type     => 'application/octet-stream',
            content_encoding => $custom_args->{content_encoding} || undef,
            headers          => $header_args,
            delivery_mode => $custom_args->{delivery_mode} || FLAG_DELIVERY,
            priority => $custom_args->{priority} || FLAG_PRIORITY,
            correlation_id => undef,
            expiration     => $custom_args->{expiration} || undef,
            message_id     => $custom_args->{message_id} || undef,
            timestamp      => time,
            type           => $custom_args->{type} || undef,
            user_id        => $user_name,
            app_id         => $custom_args->{app_id} || undef,
            cluster_id     => $custom_args->{cluster_id} || undef, ),
    ) or return;

    my $frame_chunks = [];
    @{$frame_chunks}
        = _chop_frames( $raw_msg, $custom_args->{max_frame_size} )
        or return;

    return ( $pub_frame, $frame_hdr, $frame_chunks );
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

sub _chop_frames {
    my ( $raw_msg, $max_frame_size ) = @_;
    return unless $raw_msg && $max_frame_size;
    return unpack '(a' . $max_frame_size . ')*', $raw_msg;
}

1;
