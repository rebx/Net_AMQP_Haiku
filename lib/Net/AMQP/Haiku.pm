package Net::AMQP::Haiku;

use 5.008008;
use strict;
use warnings;

require Exporter;
our @ISA    = qw(Exporter);
our @EXPORT = qw($NAME $VERSION );

our $NAME    = 'Net::AMQP::Haiku';
our $VERSION = '0.01';

use Try::Tiny;
use Carp qw(carp croak confess);
use Data::Dumper qw(Dumper);
use Net::AMQP;
use IO::Socket;
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use Net::AMQP::Haiku::Constants;
use Net::AMQP::Haiku::Properties;
use Net::AMQP::Haiku::Helpers;

sub new {
    my $class = shift;
    my $self  = {
        host           => DEFAULT_HOST,
        proto          => DEFAULT_PROTO,
        port           => DEFAULT_PORT,
        vhost          => DEFAULT_VHOST,
        username       => DEFAULT_USERNAME,
        password       => DEFAULT_PASSWORD,
        locale         => DEFAULT_LOCALE,
        queue          => DEFAULT_QUEUE,
        channel        => DEFAULT_CHANNEL,
        exchange       => DEFAULT_EXCHANGE,
        routing_key    => DEFAULT_QUEUE,
        debug          => FLAG_DEBUG,
        auth_mechanism => DEFAULT_AUTH_MECHANISM,
        is_connected   => 0,
        connection     => undef,
        timeout        => DEFAULT_TIMEOUT,
        send_retry     => SEND_RETRY,
        recv_retry     => RECV_RETRY,
        correlation_id => DEFAULT_CORRELATION_ID,
        nowait         => FLAG_NO_WAIT,
        auto_delete    => FLAG_AUTO_DELETE,
        durable        => FLAG_DURABLE,
        mandatory      => FLAG_MANDATORY,
        immediate      => FLAG_IMMEDIATE,
        consumer_tag   => DEFAULT_CONSUMER_TAG,
        no_ack         => FLAG_NO_ACK,
    };
    bless( $self, $class );
    if (@_) {
        &_parse_args( $self, @_ );
    }

    return $self;
}

###Attributes###
sub spec_file {
    my ( $self, $spec_file ) = @_;
    if ( defined($spec_file) ) {
        $self->_load_spec_file($spec_file)
            or croak "Unable to load spec file at $spec_file: $!";
    }
    return ($self);
}

sub channel {
    my ( $self, $chan ) = @_;

    if ( defined($chan) ) {
        $self->_set_channel($chan) or carp "Unable to set channel";
    }
    return ( $self->{channel} );
}

sub auth_mechanism {
    my ( $self, $auth_mechanism ) = @_;

    if ( defined($auth_mechanism) ) {
        $self->_set_auth_mechanism($auth_mechanism)
            or carp
            "Unable to set authentication mechanism to $auth_mechanism";
    }
    return ( $self->{auth_mechanism} );
}

sub debug {
    my ( $self, $debug_flag ) = @_;

    if ( defined($debug_flag) ) {
        $self->{debug} = $debug_flag;
    }
    return ( $self->{debug} );
}
###Attributes###

###Public Methods###
sub connect {
    my ($self) = @_;

    $self->_connect_sock() or return;
    $self->_connect_handshake or return;
    $self->{is_connected} = 1;
    return ( $self->{is_connected} );
}

sub open_channel {
    my ( $self, $channel ) = @_;

    $self->connect() if ( !$self->{is_connected} );
    $channel = $self->{channel} if ( !defined($channel) );
    my $open_channel
        = Net::AMQP::Protocol::Channel::Open->new( channel => $channel );

    $self->{debug}
        and print "Sending open channel frame:\n"
        . Dumper($open_channel) . "\n";
    $self->_send_frames( $open_channel, $channel ) or return;
    my ($open_channel_resp) = $self->_recv_frames() or return;

    $self->{debug}
        and print "Open channel response: "
        . Dumper($open_channel_resp) . "\n";

    if (!$open_channel_resp->method_frame->isa(
            'Net::AMQP::Protocol::Channel::OpenOk') )
    {
        carp "Unable to set channel to $channel";
        return 0;
    }
    return 1;
}

sub close_channel {
    my ( $self, $channel ) = @_;

    $channel = $self->{channel} if ( !defined($channel) );
    return unless $channel;

    my $frame_close = Net::AMQP::Frame::Method->new(
        method_frame => Net::AMQP::Protocol::Channel::Close->new() );
    $self->_send_frames($frame_close);
    my ($frame_close_resp) = $self->_recv_frames() or return;

    if (!$frame_close_resp->can('method_frame')
        or !$frame_close_resp->method_frame->isa(
            'Net::AMQP::Protocol::Channel::CloseOk') )
    {
        warn "Unable to close channel $channel properly!";
        return 0;
    }
    return 1;
}

sub close {
    my ($self) = @_;

    return 1 if ( !$self->{is_connected} );
    local $@;
    try {
        $self->close_channel( $self->{channel} );
        close( $self->{connection} )
            or die "Unable to close socket connection properly: $!\n";
    }
    catch {
        my $err = $_;
        chomp($err);
        $@ = $err;
    };
    warn $@ if ($@);
    return 1;
}

sub set_queue {
    my ( $self, $queue_name, $queue_args ) = @_;

    return unless $queue_name;

    $self->{debug} and print "Setting queue to $queue_name\n";

    my $queue_opts = def_queue_properties();
    if ( defined($queue_args) and UNIVERSAL::isa( $queue_args, 'HASH' ) ) {
        $queue_opts = { %{$queue_opts}, %{$queue_args} };
    }

    $queue_opts->{queue} = $queue_name;
    my $amqp_queue
        = Net::AMQP::Protocol::Queue::Declare->new( %{$queue_opts} );

    $self->{debug}
        and print "Declare queue frame: " . Dumper($amqp_queue) . "\n";
    $self->_send_frames($amqp_queue) or return;
    my ($resp_set_queue) = $self->_recv_frames() or return;

    $self->{debug}
        and print "set queue response: \n" . Dumper($resp_set_queue) . "\n";
    if (!$resp_set_queue->method_frame->isa(
            'Net::AMQP::Protocol::Queue::DeclareOk') )
    {
        carp "Unable to set queue name to $queue_name";
        return 0;
    }
    $self->{queue} = $queue_name;
    return 1;
}

sub send {
    my ( $self, $msg, $queue_name, $publish_args ) = @_;

    return unless $msg;

    $queue_name   ||= $self->{queue};
    $publish_args ||= {
        routing_key    => $queue_name,
        reply_to       => $queue_name,
        correlation_id => DEFAULT_CORRELATION_ID,
        channel        => $self->{channel},
        max_frame_size => $self->{tuning_parameters}->{frame_max},
    };

    my ( $pub_frame, $frame_header, $send_payload )
        = serialize( $msg, $self->{username}, $publish_args )
        or return;
    if ( $self->{debug} ) {
        print "Sending publish frame:\n" . Dumper($pub_frame) . "\n";
        print "Sending header frame:\n" . Dumper($frame_header) . "\n";
        print "Sending payload " . Dumper($send_payload) . "\n";
    }
    $self->_send_frames($pub_frame)    or return;
    $self->_send_frames($frame_header) or return;
    for my $msg_chunk ( @{$send_payload} ) {
        $self->{debug}
            and print "Sending message chunk: " . $msg_chunk . "\n";
        $self->_send_frames(
            Net::AMQP::Frame::Body->new( payload => $msg_chunk ) )
            or return 0;
    }

    return 1;
}

sub receive {
    my ( $self, $queue_name, $recv_args ) = @_;

    $queue_name ||= $self->{queue};
    if ( !defined($queue_name) ) {
        warn "No queue specified";
        return;
    }
    my $get_frame = make_get_header( $queue_name, $recv_args );
    $self->{debug} and print "Get frame:\n" . Dumper($get_frame) . "\n";
    $self->_send_frames($get_frame) or return;
    my ( $get_resp_frame, $get_resp_raw ) = $self->_recv() or return;

    my ( $resp_data, $header, $body, $footer, $size )
        = unpack_raw_data($get_resp_raw);

    my ($get_resp) = deserialize($get_resp_frame) or return;

    if ( !$get_resp->method_frame->isa('Net::AMQP::Protocol::Basic::GetOk') )
    {
        my $ret_resp = (
            (   $get_resp->method_frame->isa(
                    'Net::AMQP::Protocol::Basic::GetEmpty') ) ? '' : undef );
        return $ret_resp;
    }

    my ($queue_msg) = ( unpack_raw_data($resp_data) )[2];
    return $queue_msg;
}

sub get {
    my $self = shift;
    return $self->receive(@_);
}

sub bind_queue {
    my ( $self, $queue_name, $cust_bind_args ) = @_;

    return unless $queue_name;

    $cust_bind_args ||= {
        queue       => $queue_name,
        exchange    => $self->{exchange},
        routing_key => $queue_name,
    };

    my $bind_args = { %{ def_queue_bind_properties() }, %{$cust_bind_args} };

    my $bind_queue_frame
        = Net::AMQP::Protocol::Queue::Bind->new( %{$bind_args} );

    $self->_send_frames($bind_queue_frame) or return;

    my ($bind_resp) = $self->_recv_frames() or return;

    $self->{debug}
        and print "Got bind response:\n" . Dumper($bind_resp) . "\n";

    if (!$bind_resp->method_frame->isa('Net::AMQP::Protocol::Queue::BindOk') )
    {
        warn "Unable to bind to queue $queue_name: "
            . $bind_resp->method_frame->{reply_text};
        if ($bind_resp->method_frame->isa(
                'Net::AMQP::Protocol::Channel::Close') )
        {
            $self->close();
        }
        return;
    }
    $self->{debug} and print "Bound to queue $queue_name\n";
    return 1;
}

sub consume {
    my ( $self, $nom_args ) = @_;

    $nom_args ||= {
        ticket       => $self->{ticket},
        queue        => $self->{queue},
        consumer_tag => $self->{consumer_tag},
        no_local     => $self->{no_local},
        no_ack       => $self->{no_ack},
        exclusive    => $self->{exclusive},
        nowait       => $self->{nowait},
    };

    $nom_args = { %{ def_consume_properties() }, %{$nom_args} };

    my $nom_frame = Net::AMQP::Protocol::Basic::Consume( %{$nom_args} );

    $self->_send_frames($nom_frame) or return;
    my ($nom_resp) = $self->_recv_frames() or return;
    $self->{debug}
        and print "Got consume response:\n" . Dumper($nom_resp) . "\n";
    if (!$nom_resp->method_frame->isa(
            'Net::AMQP::Protocol::Basic::ConsumeOk') )
    {
        warn "Unable to consume from queue $nom_args->{queue}";
        return;
    }
    return 1;
}

sub nom {
    my $self = shift;
    return $self->consume(@_);
}

sub DESTROY {
    my ($self) = @_;

    $self->close();
    return 1;
}
###Public Methods###

###Private Methods###
sub _send_frames {
    my ( $self, $frame, $chan_id ) = @_;

    unless ($frame) {
        warn '' . ( caller(0) )[3] . ": No frame to send";
        return;
    }

    $chan_id = $self->{channel} if ( !defined($chan_id) );
    $self->{debug} and print "Sending frame to channel $chan_id\n";
    if ( $frame->isa('Net::AMQP::Protocol::Base') ) {
        $frame = $frame->frame_wrap();
    }
    $frame->channel($chan_id);
    $self->{debug} and print "Sending frame:\n" . Dumper($frame) . "\n";
    $self->_send( $frame->to_raw_frame() ) or return 0;
    return 1;
}

sub _recv_frames {
    my ($self) = @_;

    my ($frame) = $self->_recv() or return;
    return deserialize($frame);
}

sub _send {
    my ( $self, $payload ) = @_;

    return 0 if ( !defined($payload) );

    local $@;
    try {
        setsockopt( $self->{connection}, SOL_SOCKET, SO_SNDTIMEO,
            pack( 'L!L!', $self->{timeout}, 0 ) )
            or die
            "Unable to set socket receive timeout to $self->{timeout}: $!\n";
    }
    catch {
        my $err = $_;
        chomp($err);
        $@ = $err;
    };
    carp $@ if ($@);

    $self->{debug}
        and print "Writing payload: \n" . Dumper($payload) . "\n";
    my $payload_len = length($payload);
    local $@;
    try {
        my $sent_len = $self->{connection}->send($payload)
            or die "Unable to send data payload!: $!\n";
        die "Send error! Length mismatch: $payload_len != $sent_len"
            if ( $sent_len != $payload_len );
    }
    catch {
        my $err = $_;
        chomp($err);
        $@ = $err;
        $self->{is_connected} = 0;
        print STDERR $@ . "\n";
        $self->{debug}
            and print "Payload data was:\n" . Dumper($payload) . "\n";
    };
    return 0 if ($@);
    return 1;
}

sub _recv {
    my ($self) = @_;

    $self->_set_recv_timeout();

    my ( $data, $data_len ) = $self->_read_socket(DEFAULT_RECV_LEN);

    unless ($data) {
        $data = $self->_read_socket(DEFAULT_RECV_LEN) or return;
    }
    my ( $header, $body, $footer, $size );

    ( $header, $size, $data ) = unpack_data_header($data) or return;
    ( $body, $data ) = unpack_data_body( $data, $size ) or return;

    # Do we have more to read?
    if ( length $body < $size || length $data == 0 ) {
        my $size_remaining = $size + _FOOTER_LENGTH - length $body;
        while ( $size_remaining > 0 ) {
            my $chunk = $self->_read_socket($size_remaining) or return;
            $size_remaining -= length $chunk;
            $data .= $chunk;
        }
        my ($tmp_bod) = unpack_data_body( $data, $size - length($body) )
            or return;
        $body .= $tmp_bod;
    }
    ( $footer, $data ) = unpack_data_footer($data) or return;

    my $full_msg = $header . $body . $footer;
    return ( $full_msg, $data );
}

sub _set_recv_timeout {
    my ( $self, $recv_timeout ) = @_;

    $recv_timeout ||= $self->{timeout};

    local $@;
    try {
        setsockopt( $self->{connection}, SOL_SOCKET, SO_RCVTIMEO,
            pack( 'L!L!', $recv_timeout, 0 ) )
            or die
            "Unable to set socket receive timeout to $self->{timeout}: $!\n";
    }
    catch {
        my $err = $_;
        chomp($err);
        $@ = $err;
    };
    if ($@) {
        warn $@;
        return 0;
    }

    return 1;
}

sub _read_socket {
    my ( $self, $length ) = @_;

    # default length is header + emty body + footer
    $length = _HEADER_LENGTH + _HEADER_LENGTH if ( !defined($length) );
    $self->{debug}
        and print "_read_socket is reading $length characters\n";
    my ( $payload, $data_len );
    for ( my $i = 1; $i < RECV_RETRY; $i++ ) {

        local $@;
        try {
            $data_len = $self->{connection}->sysread( $payload, $length )
                or die "Unable to read socket: $!\n";
            $self->{debug}
                and print "Read $data_len of $length characters of data\n";
        }
        catch {
            my $err = $_;
            chomp($err);
            $@ = $err;
            $self->{is_connected} = 0 if ( $err =~ /read from socket/ );
            $self->{debug}
                and print "Dumped payload: \n" . Dumper($payload) . "\n";
            $self->{debug} and print STDERR $@ . "\n";
        };
        return ( $payload, $data_len ) if ( !$@ );
    }
    return;
}

sub _load_spec_file {
    my ( $self, $spec_file ) = @_;
    if ( !defined($spec_file) ) {
        croak "No spec file given!";
    }
    croak "AMQP spec file $spec_file does not exist: $!"
        if ( !-e "$spec_file" );
    Net::AMQP::Protocol->load_xml_spec($spec_file);
    return 1;
}

sub _set_channel {
    my ( $self, $chan ) = @_;

    $self->{channel} = $chan;
    return 1;
}

sub _set_auth_mechanism {
    my ( $self, $auth_mechanism ) = @_;

    if ( exists( $AUTH_MECHANISM_LIST->{"$auth_mechanism"} ) ) {
        $self->{auth_mechanism} = $auth_mechanism;
    }

    return 1;
}

sub _client_properties {
    return {
        platform => CLIENT_PLATFORM,
        product  => $NAME,
        version  => $VERSION,
    };
}

sub _parse_args {
    my ( $self, $list_params ) = @_;

    while ( my ( $key, $value ) = each( %{$list_params} ) ) {
        if ( $self->can($key) ) {
            $self->$key($value);
            next;
        }
        $self->{$key} = $value;
    }
    return;
}

sub _connect_sock {
    my ($self) = @_;

    return $self->{connection} if $self->{is_connected};

    my $amqp_sock;
    local $@;
    try {
        $amqp_sock = IO::Socket::INET->new(
            PeerAddr => $self->{host},
            PeerPort => $self->{port},
            Proto    => $self->{proto},
            Timeout  => $self->{timeout}
        ) or die "Unable to connect to $self->{host}:$self->{port}: $!\n";
        setsockopt( $amqp_sock, IPPROTO_TCP, TCP_NODELAY, 1 )
            or die "Unable to set tcp_nodelay to 1: $!\n";
    }
    catch {
        my $err = $_;
        chomp($err);
        $@ = $err;
    };
    carp $@ if ($@);
    $self->{debug}
        and print
        "Raw connection established to amqp host $self->{host}:$self->{port}\n";

    $self->{connection} = $amqp_sock;

    return ( $self->{connection} );
}

sub _connect_handshake {
    my ($self) = @_;

    # greet the server...OHAI!!!
    $self->{debug} and print "Sending greeting to server $self->{host}\n";
    local $@;
    try {
        $self->_send( Net::AMQP::Protocol->header() )
            or die
            "Unable to send amqp protocol header to $self->{host}:$self->{port}: $!\n";
    }
    catch {
        my $err = $_;
        chomp($err);
        $@ = $err;
    };
    carp "server greeting failed: $@" if ($@);

    # check if you got a Connection::Start frame back
    my ($resp_frame) = $self->_recv_frames() or return;
    $self->{debug}
        and print "Greeting result: " . Dumper($resp_frame) . "\n";
    if (!$resp_frame->isa('Net::AMQP::Frame::Method')
        or !$resp_frame->method_frame->isa(
            'Net::AMQP::Protocol::Connection::Start') )
    {
        carp "Invalid greeting response: " . Dumper($resp_frame);
    }
    $self->_check_server_capabilities($resp_frame) or return;

    # Now send startok
    $self->{debug}
        and print "Starting connection to server $self->{host}\n";
    my $shake_frame = Net::AMQP::Protocol::Connection::StartOk->new(
        client_properties => _client_properties(),
        mechanism         => $self->{auth_mechanism},
        response          => {
            LOGIN    => $self->{username},
            PASSWORD => $self->{password},
        },
        locale => $self->{locale}, );
    $self->{debug}
        and print "Sending startok frame " . Dumper($shake_frame) . "\n";
    $self->_send_frames( $shake_frame, HANDSHAKE_CHANNEL ) or return;

    # check if you got a Connection::Tune frame back
    my ($resp_shake) = $self->_recv_frames() or return;
    $self->{debug}
        and print "Start connection response: " . Dumper($resp_shake) . "\n";

    if ($resp_shake->can('method_frame')
        and !$resp_shake->method_frame->isa(
            'Net::AMQP::Protocol::Connection::Tune') )
    {
        carp "expecting Connection::Tune class response but got "
            . Dumper($resp_shake);
    }

    @{ $self->{tuning_parameters} }{ keys %{ $resp_shake->method_frame } }
        = values( %{ $resp_shake->method_frame } );
    $self->{debug}
        and print "tuning parameters:\n"
        . Dumper $self->{tuning_parameters} . "\n";

    # send tuning params
    my $tune_frame = Net::AMQP::Protocol::Connection::TuneOk->new(
        %{ $self->{tuning_parameters} } );

    $self->{debug} and print "Tune frame: " . Dumper($tune_frame) . "\n";
    $self->_send_frames( $tune_frame, HANDSHAKE_CHANNEL ) or return;

    # Send the Connection::Open frame
    my $open_conn = Net::AMQP::Protocol::Connection::Open->new(
        virtual_host => $self->{vhost},
        capabilities => '',
        insist       => 1, );
    $self->{debug}
        and print "Sending connection open frame:\n"
        . Dumper($open_conn) . "\n";
    $self->_send_frames( $open_conn, HANDSHAKE_CHANNEL ) or return;

    # Check if you got the Connection::OpenOk frame back
    my ($resp_open) = $self->_recv_frames() or return;
    $self->{debug}
        and print "Frame open response: \n" . Dumper($resp_open) . "\n";
    if (!$resp_open->method_frame->isa(
            'Net::AMQP::Protocol::Connection::OpenOk') )
    {
        carp "Unable to establish initial communication properly. ";
        $self->{debug}
            and print "Server response is: " . Dumper($resp_open);
        return 0;
    }

    return 1;
}

sub _check_server_capabilities {
    my ( $self, $server_caps ) = @_;

    $self->{debug} and print "Checking server capabilities\n";
    return unless $server_caps;

    map { $self->{server_auth_mechanisms}->{$_} = 1 }
        split( /\s+/, $server_caps->method_frame->mechanisms );
    if (!exists(
            $self->{server_auth_mechanisms}->{ $self->{auth_mechanism} } ) )
    {
        carp 'Authentication mechanism '
            . $self->{auth_mechanism}
            . " is not available on the server. \n"
            . "Options available are: "
            . join( ",", keys( %{ $self->{server_auth_mechanisms} } ) );
    }
    map { $self->{server_locales}->{$_} = 1 }
        split( /\s+/, $server_caps->method_frame->locales );
    if ( !exists( $self->{server_locales}->{ $self->{locale} } ) ) {
        carp "The locale $self->{locale} is not available on the server.\n"
            . "Available options are: "
            . join( ",", keys( %{ $self->{server_locales} } ) );
    }
    $self->{debug} and print "Server capabilities are ok\n";
    return 1;
}

###Private Methods###

1;
__END__

=head1 NAME

Net::AMQP::Haiku - A simple Perl extension for AMQP.

=head1 SYNOPSIS

  use Net::AMQP::Haiku;
  my $amqp = Net::AMQP::Haiku->new({
    host=> 'localhost',
    spec_file => '/path/to/spec/file/amqp'
  });
  $amqp->open_channel();
  $amqp->set_queue('foo');
  $amqp->send("ohai!");
  print $amqp->receive();

=head1 DESCRIPTION

    The design for this module is to be as simple as possible -- use only the
standard perl libraries, apart from Net::AMQP, and be compatible from
Perl version 5.8.8.

=head2 EXPORT

NAME
VERSION


=head1 SEE ALSO

Other useful references:

=item Net::AMQP

http://search.cpan.org/dist/Net-AMQP/lib/Net/AMQP.pm

=item Net::AMQP::Simple

https://github.com/norbu09/Net_AMQP_Simple

=item Net::Thumper

https://github.com/Mutant/Net-Thumper

=back

=item 

=head1 AUTHOR

Rebs Guarina, E<lt>rebs.guarina@gmail.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Rebs Guarina

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
