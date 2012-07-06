package Net::AMQP::Haiku::Helpers;

use strict;
require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw(deserialize serialize make_get_header
    unpack_data_header unpack_data_body unpack_data_footer unpack_raw_data
    );

use Data::Dumper qw(Dumper);
use Net::AMQP;
use Net::AMQP::Haiku::Constants;
use Net::AMQP::Haiku::Properties;

sub deserialize {
    my ($data) = @_;
    return unless $data;
    return Net::AMQP->parse_raw_frames( \$data );
}

sub unpack_data_header {
    my ($data) = @_;

    return unless $data;

    my $header = substr $data, 0, _HEADER_LENGTH, '';
    return unless $header;
    my ( $type_id, $channel, $size ) = unpack 'CnN', $header;

    return ( $header, $size, $data, $type_id, $channel );
}

sub unpack_data_body {
    my ( $data, $size ) = @_;

    return unless $data && $size;

    my $body = substr $data, 0, $size, '' or return;

    return ( $body, $data );
}

sub unpack_data_footer {
    my ($data) = @_;

    # Read the footer and check the octet value
    my $footer = substr $data, 0, _FOOTER_LENGTH, '';
    my $footer_octet = unpack 'C', $footer;

    # TEH FOOTER MUST EXISTETH!
    if ( !defined($footer_octet) or ( $footer_octet != _FOOTER_OCT ) ) {
        warn "Invalid footer: $footer_octet\n";
        return;
    }

    return ( $footer, $data );
}

sub unpack_raw_data {
    my ($resp_data) = @_;

    my ( $header, $size, $body, $footer );
    ( $header, $size, $resp_data ) = unpack_data_header($resp_data) or return;
    ( $body, $resp_data ) = unpack_data_body( $resp_data, $size );
    ( $footer, $resp_data ) = unpack_data_footer($resp_data) or return;

    return ( $resp_data, $header, $body, $footer, $size );
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
    my ( $queue, $extra_args ) = @_;

    return unless $queue;
    $extra_args ||= { ticket => DEFAULT_TICKET };

    # in a synchronous world
    return Net::AMQP::Protocol::Basic::Get->new(
        no_ack => FLAG_NO_ACK,
        queue  => $queue,
        %{$extra_args}, );
}

sub _chop_frames {
    my ( $raw_msg, $max_frame_size ) = @_;
    return unless $raw_msg && $max_frame_size;
    return unpack '(a' . $max_frame_size . ')*', $raw_msg;
}

1;
