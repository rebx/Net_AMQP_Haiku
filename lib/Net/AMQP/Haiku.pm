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

#use Net::AMQP::Common qw(:all);
#use Net::AMQP::Frame;
#use Net::AMQP::Protocol;
#use Net::AMQP::Protocol::Base;
use Net::AMQP::Protocol::v0_8;
use IO::Socket;
use Socket qw(IPPROTO_TCP TCP_NODELAY);
use Net::AMQP::Haiku::Constants;

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
        debug          => FLAG_DEBUG,
        auth_mechanism => DEFAULT_AUTH_MECHANISM,
        is_connected   => 0,
        connection     => undef,
        timeout        => DEFAULT_TIMEOUT,
        send_retry     => SEND_RETRY,
        recv_retry     => RECV_RETRY,
        correlation_id => DEFAULT_CORRELATION_ID,
    };
    bless( $self, $class );
    if (@_) {
        &_parse_args( $self, @_ );
    }

    #$self->connect();
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
    $channel ||= $self->{channel};
    my $chan = Net::AMQP::Protocol::Channel::Open->new( channel => $channel );

    my $open_channel_frame = Net::AMQP::Frame::Method->new(
        channel      => $channel,
        method_frame => Net::AMQP::Protocol::Channel::Open->new(), );
    $self->_send_frames($open_channel_frame);
    my ($open_channel_resp) = $self->_recv();

    $self->{debug}
        and print "Open channel response: "
        . Dumper($open_channel_resp) . "\n";

    if (!$open_channel_resp->method_frame->isa(
            'Net::AMQP::Protocol::Channel::OpenOk') )
    {
        return 0;
    }
    return 1;
}

sub close_channel {
    my ( $self, $channel ) = @_;

    $channel ||= $self->{channel};
    return unless $channel;

    my $frame_close = Net::AMQP::Frame::Method->new(
        method_frame => Net::AMQP::Protocol::Channel::Close->new() );
    $self->_send_frames($frame_close);
    my @frames = $self->_read();

    for my $frame (@frames) {
        return 1
            if (
            $frame->isa('Net::AMQP::Frame::Method')
            and $frame->method_frame->isa(
                'Net::AMQP::Protocol::Channel::CloseOk') );
    }
    warn "Unable to close channel $channel properly!";
    return 0;
}

sub close {
    my ($self) = @_;

    return 1 if ( !$self->{is_connected} );
    $self->close_channel( $self->{channel} );
    local $@;
    try {
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
    my ( $self, $queue_name ) = @_;

    return unless $queue_name;

    $self->{debug} and print "Setting queue to $queue_name\n";
    my $queue_opts = _queue_properties();
    $queue_opts->{queue} = $queue_name;
    my $amqp_queue
        = Net::AMQP::Protocol::Queue::Declare->new( %{$queue_opts} );

    $self->{debug}
        and print "Declare queue frame: " . Dumper($amqp_queue) . "\n";
    $self->_send_frames($amqp_queue) or return;
    my ($resp_set_queue) = $self->_recv() or return;

    if (!$resp_set_queue->method_frame->isa(
            'Net::AMQP::Protocol::Queue::DeclareOk') )
    {
        carp "Unable to set queue name to $queue_name";
        return 0;
    }
    return 1;
}

sub send {
    my ( $self, $msg ) = @_;

    return unless $msg;

    my $payload = $self->_serialize($msg);
    $self->{debug} and print "Sending payload " . Dumper($payload) . "\n";
    $self->_send($payload);
    return 1;
}

sub receive {
    my ($self) = @_;

    my @frames = $self->_recv() or return;

    my $mesg;
    for my $frame (@frames) {
        $mesg .= $frame->payload();
    }

    return $mesg;
}

sub get {
    my ($self) = @_;
    return $self->receive();
}

sub consume {

}

sub nom {
    my ($self) = @_;
    return $self->consume();
}

sub DESTROY {
    my ($self) = @_;

    $self->close();
    return 1;
}
###Public Methods###

###Private Methods###
sub _send_frames {
    my ( $self, $frame, $chan ) = @_;

    $chan ||= $self->{channel};
    if ( $frame->isa('Net::AMQP::Protocol::Base') ) {
        $frame = $frame->frame_wrap();
    }
    $frame->channel($chan);

    $self->_send( $frame->to_raw_frame() ) or return 0;
    return 1;
}

sub _recv_frames {
    my ($self) = @_;

    my @frames = $self->_recv();
    return @frames;
}

sub _send {
    my ( $self, $payload ) = @_;

    return 0 if ( !defined($payload) );
    $self->_connect_sock()
        if ( !$self->{connection}->isa('IO::Socket::INET') );
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
    };
    return 0 if ($@);
    return 1;
}

sub _recv {
    my ($self) = @_;
    $self->_connect_sock()
        if ( !$self->{connection}->isa('IO::Socket::INET') );
    my @frames = ();

    my ( $type_id, $channel, $payload );

    # read teh amqp header first
    my $hdr_len = _HEADER_LENGTH + 1;
    my ( $data, $read_len ) = $self->_read_socket($hdr_len) or return 0;

    # get the lenght of data we need to read
    my $data_len = ( _unpack_raw_data($data) )[2];

    #if ( $data_len < _HEADER_LENGTH ) {
    #    #$data .= $self->_read_socket(1024) or return;
    #    warn "Socket response length is less than header length!"
    #}

    $self->{debug} and print "Reading data of length $data_len\n";

    while ( $data_len > 0 ) {
        my ( $payload, $payload_len ) = $self->_read_socket($data_len)
            or return;
        $data_len -= $payload_len;
        $data .= $payload;
        $self->{debug} and print "read payload: " . Dumper($payload);
    }
    $self->{debug} and print "read data: " . Dumper($data);

    return _deserialize($data);
}

sub _unpack_raw_data {
    my ($data) = @_;
    return unless $data;
    return unpack 'CnN', substr $data, 0, 7, '';
}

sub _read_socket {
    my ( $self, $length ) = @_;

    local $@;
    try {
        setsockopt( $self->{connection}, SOL_SOCKET, SO_RCVTIMEO,
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
    $length ||= _HEADER_LENGTH + 1;
    $self->{debug}
        and print "_read_socket is reading $length characters\n";
    my ( $payload, $data_len );
    for ( my $i = 1; $i < RECV_RETRY; $i++ ) {

        local $@;
        try {
            $data_len = read( $self->{connection}, $payload, $length )
                or die "Unable to read socket: $!\n";
            die "Socket read error! Length mismatch! $data_len vs $length\n"
                if ( $data_len != $length );
            $self->{debug} and print "Read $length characters of data\n";
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

sub _deserialize {
    my ($data) = @_;
    return unless $data;

    return Net::AMQP->parse_raw_frames( \$data );
}

sub _serialize {
    my ( $self, $data, $channel, $args, $header_args, $mandatory, $immediate,
        $ticket )
        = @_;

    $channel ||= $self->{channel};
    my $ser_frame = Net::AMQP::Protocol::Basic::Publish->new(
        exchange  => $self->{exchange},
        mandatory => $mandatory,
        immediate => $immediate,
        %{$args},
        ticket => $ticket, );

    my $frame_hdr = Net::AMQP::Protocol::Basic::ContentHeader->new(
        content_type     => 'application/octet-stream',
        content_encoding => undef,
        headers          => {},
        delivery_mode    => 1,
        priority         => 1,
        correlation_id   => 1234,
        expiration       => undef,
        message_id       => undef,
        timestamp        => time,
        type             => undef,
        user_id          => $self->{user_name},
        app_id           => undef,
        cluster_id       => undef,
        %{$header_args}, );

    my $frame_bdy = Net::AMQP::Frame::Body->new( payload => $data );
    my $frame_pub = $ser_frame->frame_wrap();
    $frame_pub->channel( $self->{channel} );
    $frame_hdr->channel( $self->{channel} );
    $frame_bdy->channel( $self->{channel} );

    return
          $frame_pub->to_raw_frame()
        . $frame_hdr->to_raw_frame()
        . $frame_bdy->to_raw_frame();
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

sub _queue_properties {

    return {
        ticket       => 0,
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

sub _parse_args {
    my ( $self, $list ) = @_;

    while ( my ( $key, $value ) = each( %{$list} ) ) {
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

    # greet the server
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

    my ($resp_frame) = $self->_recv() or return;
    $self->{debug}
        and print "Greeting result: " . Dumper($resp_frame) . "\n";
    if (!$resp_frame->isa('Net::AMQP::Frame::Method')
        or !$resp_frame->method_frame->isa(
            'Net::AMQP::Protocol::Connection::Start') )
    {
        carp "Invalid greeting response: " . Dumper($resp_frame);
    }
    $self->_check_server_capabilities($resp_frame) or return;

    # send startok
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
    $self->_send_frames($shake_frame) or return;

    my ($resp_shake) = $self->_recv() or return;

    $self->{debug}
        and print "Start connection response: " . Dumper($resp_shake) . "\n";

    if ($resp_shake->can('method_frame')
        and !$resp_shake->method_frame->isa(
            'Net::AMQP::Protocol::Connection::Tune') )
    {
        carp "expecting Connection::Tune class response but got "
            . Dumper($resp_shake);
    }

    # send tuning params
    my $tune_frame = Net::AMQP::Protocol::Connection::TuneOk->new(
        channel_max => $resp_shake->method_frame->channel_max,
        frame_max   => $resp_shake->method_frame->frame_max,
        heartbeat   => $resp_shake->method_frame->heartbeat, );

    $self->{debug} and print "Tune frame: " . Dumper($tune_frame) . "\n";
    $self->_send_frames($tune_frame) or return;

    # open the connection
    my $open_conn = Net::AMQP::Protocol::Connection::Open->new(
        virtual_host => $self->{vhost},
        capabilities => '',
        insist       => 1, );
    $self->_send_frames($open_conn) or return;

    my ($resp_open) = $self->_recv() or return;

    $self->{debug}
        and print "Frame open response: \n" . Dumper($resp_open) . "\n";
    if (!$resp_open->method_frame->isa(
            'Net::AMQP::Protocol::Connection::OpenOk') )
    {
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
  $amqp = Net::AMQP::Haiku->new({
    host=> 'localhost',
    spec_file => '/path/to/spec/file/amqp
  });
  $amqp->open_channel();
  $amqp->send("ohai!");

=head1 DESCRIPTION

    The design for this module is to be as simple as possible -- use only the
standard perl libraries, apart from Net::AMQP, and be compatible from
Perl version 5.8.8.


=head2 EXPORT

NAME
VERSION


=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Rebs Guarina, E<lt>rebs.guarina@gmail.com<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2012 by Rebs Guarina

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.8 or,
at your option, any later version of Perl 5 you may have available.


=cut
