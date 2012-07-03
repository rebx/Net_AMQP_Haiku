package Net::AMQP::Haiku::Helpers;

use strict;
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(deserialize serialize make_get_header);

use Net::AMQP;
use Net::AMQP::Protocol::v0_8;
use Net::AMQP::Haiku::Constants;

sub deserialize {
    my ($data) = @_;
    return unless $data;

    return Net::AMQP->parse_raw_frames( \$data );
}

sub serialize {
    my ( $data, $exchange, $mandatory, $immediate, $args, $ticket, $user_name,
        $header_args )
        = @_;

    return unless $data;
    $exchange ||= '';
    $mandatory // 0;
    $immediate // 0;
    $ticket    // 0;
    my $weight = $header_args->{weight} || 0;

    my $pub_frame = Net::AMQP::Protocol::Basic::Publish->new(
        exchange  => $exchange,
        mandatory => $mandatory,
        immediate => $immediate,
        %{$args},
        ticket => $ticket, );

    my $frame_hdr = Net::AMQP::Frame::Header->new(
        weight       => $weight,
        body_size    => length($data),
        header_frame => Net::AMQP::Protocol::Basic::ContentHeader->new(
            content_type     => 'application/octet-stream',
            content_encoding => undef,
            headers          => {},
            delivery_mode    => 1,
            priority         => 1,
            correlation_id   => DEFAULT_CORRELATION_ID,
            expiration       => undef,
            message_id       => undef,
            timestamp        => time,
            type             => undef,
            user_id          => $user_name,
            app_id           => undef,
            cluster_id       => undef, ), );

    my $frame_body = Net::AMQP::Frame::Body->new( payload => $data );
    $pub_frame = $pub_frame->frame_wrap();

    my $raw_frame
        = $pub_frame->to_raw_frame
        . $frame_hdr->to_raw_frame
        . $frame_body->to_raw_frame;
    return $raw_frame;
}

sub make_get_header {
    my ($queue, $ticket, $extra_args) = @_;
    
    return unless $queue;
    $ticket // 0;
    $extra_args ||= {};
    # in an asynchronous world
    return Net::AMQP::Protocol::Basic::Get->new(
        no_ack => 1,
        queue => $queue,
        ticket => $ticket,
        %{$extra_args},
    );
}

1;
