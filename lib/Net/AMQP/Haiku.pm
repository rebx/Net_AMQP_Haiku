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
        exchange_name  => DEFAULT_EXCHANGE_NAME,
        exchange_type  => DEFAULT_EXCHANGE_TYPE,
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
    if ( !$self->_check_frame_response('Net::AMQP::Protocol::Channel::OpenOk')
        )
    {
        warn "Unable to set channel to $channel";
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

    if (!$self->_check_frame_response(
            'Net::AMQP::Protocol::Channel::CloseOk') )
    {
        warn "Unable to close channel $channel";
        return 0;
    }

    return 1;
}

sub close_connection {
    my ($self) = @_;

    my $close_frame = Net::AMQP::Protocol::Connection::Close->new();
    $self->_send_frames( $close_frame, HANDSHAKE_CHANNEL );

    return 0
        if (
        !$self->_check_frame_response(
            'Net::AMQP::Protocol::Connection::CloseOk') );
    return 1;
}

sub close {
    my ($self) = @_;

    return 1 if ( !$self->{is_connected} );
    local $@;
    try {
        $self->close_connection()
            or die "Unable to send Connection::Close frame properly\n";
    }
    catch {
        my $err = $_;
        chomp($err);
        $@ = $err;

        # nobody cares?
        warn $@ if ( $@ and $self->{debug} );
    };
    return 0 if ($@);
    return 1;
}

=item set_queue

    Sets the name of the queue you want to receive/send messages from/to
    
    Arguments
    
    queue_name - the name of the queue
    queue_args - a hash which can contain the following attributes
    
        ticket - the access realm
        queue - the name of the queue [automatically populated]
        passive - don't create the queue
        durable - make the queue persistent
        exclusive - have only this connection consume from the queue. implies auto_delete (See below)
        auto_delete - automatically delete the queue when all consumers exit
        nowait - don't send a reply after a method request
        
    The function returns 1 on success; 0 or none otherwise
    
=cut

sub set_queue {
    my ( $self, $queue_name, $queue_args ) = @_;

    return unless $queue_name;

    $self->connect() if ( !$self->{is_connected} );
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

    if (!$self->_check_frame_response(
            'Net::AMQP::Protocol::Queue::DeclareOk') )
    {
        warn "Unable to set the queue to $queue_name";
        return 0;
    }

    $self->{queue} = $queue_name;
    return 1;
}

=item set_exchange

    binds an exchange to the queue
    
    Arguments
    
    exchange_name - the name of the exchange
    exchange_args - a hash of attributes
        ticket
        exchange [automatically populated]
        type [fanout|direct|topic]
        passive
        durable
        auto_delete
        internal
        nowait
        [extra args]
        
    Returns 1 on success; 0 or none otherwise
        
=cut

sub set_exchange {
    my ( $self, $exchange_name, $exchange_args ) = @_;

    return unless $exchange_name;
    $exchange_name ||= $self->{exchange_name};
    $exchange_args ||= {
        exchange => $exchange_name,
        type     => DEFAULT_EXCHANGE_TYPE
    };
    $exchange_args->{exchange} = $exchange_name
        if ( !exists( $exchange_args->{exchange} ) );
    my $def_exchange_args = def_exchange_properties();
    $exchange_args = { %{$def_exchange_args}, %{$exchange_args} };

    Net::AMQP::Haiku::Helpers::check_exchange_type( $exchange_args->{type} )
        or return;

    my $exchange_frame
        = Net::AMQP::Protocol::Exchange::Declare->new( %{$exchange_args} );
    $self->_send_frames($exchange_frame) or return;

    if (!$self->_check_frame_response(
            'Net::AMQP::Protocol::Exchange::DeclareOk') )
    {
        warn "Unable to set the exchange to $exchange_name";
        return 0;
    }
    $self->{exchange} = $exchange_name;
    $self->{debug} and print "Set the exchange as $self->{exchange}\n";
    return 1;
}

=item send

    Sends/Publishes a message to the queue
    
    Arguments
    
    msg - the message being sent
    queue_name - the name of the queue to publish to
    publish args - a hash that can have the following entries
    
        routing_key
        reply_to
        correlation_id
        channel
        exchange
        ticket
        immediate
        mandatory
        
        
    The function returns a value of 1 if the message is sent properly. If it
    fails to do so, either none or 0 will be given back
    
    Example
    
    $amqp->send("foo");
    $amqp->send("foo", "testqueue", {routing_key => "testroute"
        reply_to => "testreply", correlation_id=>72, channel=> 75});
    
=cut

sub send {
    my ( $self, $msg, $queue_name, $publish_args ) = @_;

    return unless $msg;

    $queue_name   ||= $self->{queue};
    $publish_args ||= {};

    # frame size should be
    # max frame size -
    # (header payload +footer payload + null string paded by unpack)
    $publish_args->{max_frame_size} = $self->{tuning_parameters}->{frame_max}
        - ( _HEADER_LENGTH + _FOOTER_LENGTH + 1 );
    $publish_args->{routing_key} ||= $queue_name;
    $publish_args->{reply_to}    ||= $queue_name;
    $publish_args->{channel}     ||= $self->{channel};

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

=item receive

    Pulls messages off a queue.
    
    Arguments
    
    queue_name - the name of the queue. Optional, if default settings are used
    recv_args - a hash that can contain the following attributes
        ticket
        queue       - optional. filled in from the queue_name argument
        no_ack      - don't send acknowledgements to the server
        reply_to    - specify a reply to name
        routing_key - specify the routing key name
        exchange    - the name of the exchange
        
    The function returns the message pulled off the queue on success.
    On failure, it will return an empty string if the server's response is
    GetEmpty; undef will be returned otherwise
    
=cut

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

    my ( $get_resp_frame, $get_resp_content ) = $self->_recv()
        or return;

    # unpack the response frame and check if it's a GetOk
    my ($get_resp) = deserialize($get_resp_frame) or return;
    if ( !$get_resp->method_frame->isa('Net::AMQP::Protocol::Basic::GetOk') )
    {
        my $ret_resp = (
            (   $get_resp->method_frame->isa(
                    'Net::AMQP::Protocol::Basic::GetEmpty') ) ? '' : undef );
        return $ret_resp;
    }
    $self->{debug}
        and print "Got Basic::GetOk response:\n" . Dumper($get_resp) . "\n";

    # now that we've got an ack that we have a content,
    # let's parse that too...

    my ( $get_resp_data, $get_header, $get_body, $get_footer, $get_size )
        = unpack_raw_data($get_resp_content);

    # check if we've got a real content header back
    # deserialize the header, body and footer of that content
    my ($get_body_frame)
        = deserialize( $get_header . $get_body . $get_footer )
        or return;
    if (!UNIVERSAL::isa( $get_body_frame, 'Net::AMQP::Frame::Header' )
        or !$get_body_frame->header_frame->isa(
            'Net::AMQP::Protocol::Basic::ContentHeader') )
    {
        warn "Unexpected response from server after Basic::GetOk:\n"
            . Dumper($get_body_frame);
        return;
    }
    $self->{debug}
        and print "Get body frame:\n" . Dumper($get_body_frame) . "\n";

    my ( $msg_body, $msg_tail, $msg_footer );
    my $full_msg_body = $msg_body = '';
    $msg_tail = $get_resp_data;
    while ( length($full_msg_body) < $get_body_frame->{body_size} ) {

        # check if we alfready have data. otherwise get some more...
        unless ($msg_tail) {
            ($msg_tail) = $self->_read_socket(DEFAULT_RECV_LEN);
        }

        # now let's unpack the header from the content and see if we have
        # more to fetch
        my ( $content_size, $content_data )
            = ( unpack_data_header($msg_tail) )[ 1, 2 ];

        # now see how much message we have by unpacking the body
        ( $msg_body, $msg_tail )
            = unpack_data_body( $content_data, $content_size );

        # check if the data we have is complete
        ( $msg_body, $msg_tail )
            = $self->_has_more_data( $msg_body, $msg_tail, $content_size );

        # now unpack the footer
        ( $msg_footer, $msg_tail ) = unpack_data_footer($msg_tail) or return;
        $full_msg_body .= $msg_body;
    }
    return $full_msg_body;
}

sub get {
    my $self = shift;
    return $self->receive(@_);
}

=item bind_queue

    bind an exchang to a queue
    
    expects a hash with attributes
        
        queue
        routing_key
        exchange
=cut

sub bind_queue {
    my ( $self, $cust_bind_args ) = @_;

    my $queue_name = (
        ( defined( $cust_bind_args->{queue} ) )
        ? $cust_bind_args->{queue}
        : $self->{queue} );

    unless ($queue_name) {
        warn "No queue has been named";
        return;
    }

    $cust_bind_args ||= {};

    $cust_bind_args->{queue} = $queue_name
        if ( !exists( $cust_bind_args->{queue} ) );
    $cust_bind_args->{routing_key} = $queue_name
        if ( !exists( $cust_bind_args->{routing_key} ) );
    $cust_bind_args->{exchange} = $queue_name
        if ( !exists( $cust_bind_args->{exchange} ) );

    my $def_bind_args = def_queue_bind_properties();
    my $bind_args = { %{$def_bind_args}, %{$cust_bind_args} };

    my $bind_queue_frame
        = Net::AMQP::Protocol::Queue::Bind->new( %{$bind_args} );

    $self->_send_frames($bind_queue_frame) or return;

    if ( !$self->_check_frame_response('Net::AMQP::Protocol::Queue::BindOk') )
    {
        warn
            "Unable to bind queue $queue_name to exchange $bind_args->{exchange}";
        return 0;
    }

    $self->{debug}
        and print "Bound to queue $queue_name "
        . "to exchange $bind_args->{exchange}\n";
    return 1;
}

=item consume_queue

    Sends a notice to the server to let it know that the client wants to
    register itself as a consumer
    
    Arguments
    
    queue_name - the name of the queue being consumed from
    cust_nom_args - a hash which can have the following attributes
        ticket
        queue [automatically populated from the queue_name]
        consumer_tag - the designated name of the consumer [automatically generated]
        no_local - the publisher won't be able to consume its own messages
        no_ack - server does not expect acknowledgments for messages
        exclusive - request exclusive client access
        nowait - the client will not wait for the reply method
        
    The function returns 1 (true) if the server responses with ConsumeOk.
    Zero or None will be handed back in the event of a failure
    
=cut

sub consume_queue {
    my ( $self, $queue_name, $cust_nom_args ) = @_;

    return unless $queue_name;

    $cust_nom_args ||= {};
    $cust_nom_args->{queue} ||= $queue_name;

    my $def_nom_args = def_consume_properties();
    my $nom_args = { %{$def_nom_args}, %{$cust_nom_args} };

    my $nom_frame = Net::AMQP::Protocol::Basic::Consume->new( %{$nom_args} );

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
    $self->{consumer_tag} = $nom_resp->method_frame->consumer_tag;
    $self->{debug}
        and print "Ready to consume from queue "
        . $queue_name
        . "using consumer tag $self->{consumer_tag}\n";
    return 1;
}

sub consume {
    my $self = shift;
    return $self->nom(@_);
}

=item nom

    consumes messages from a queue, after sending Consume frame
    
=cut

sub nom {
    my ($self) = @_;

    unless ( $self->{consumer_tag} ) {
        carp "consumer_tag attribute is not defined. "
            . "call consume_queue() method first";
    }

    my ( $nom_resp_frame, $nom_raw_data ) = $self->_recv() or return;

    my ($nom_frame) = deserialize($nom_resp_frame) or return;
    if ( !$nom_frame->method_frame->isa('Net::AMQP::Protocol::Basic::Deliver')
        )
    {
        warn "Got invalid response frame back while "
            . "consuming from $self->{queue} queue";
        print STDERR "Frame response is:\n" . Dumper($nom_frame) . "\n";
        return;
    }
    my ( $nom_data, $nom_hdr, $nom_bod, $nom_ftr, $size )
        = unpack_raw_data($nom_raw_data);

    my ($nom_msg) = ( unpack_raw_data($nom_data) )[2];
    $self->{debug} and print "Consumed message: \'" . $nom_msg . "\'\n";
    return $nom_msg;
}

sub purge_queue {
    my ( $self, $queue_name, $purge_args ) = @_;

    return unless $queue_name;

    $purge_args ||= {};
    my $def_purge_args
        = Net::AMQP::Haiku::Properties::def_queue_purge_properties();
    $purge_args->{queue} = $queue_name;
    $purge_args = { %{$def_purge_args}, %{$purge_args} };

    my $purge_frame
        = Net::AMQP::Protocol::Queue::Purge->new( %{$purge_args} );
    $self->_send_frames($purge_frame) or return;

    my ($purge_resp) = $self->_recv_frames() or return;

    if (!$purge_resp->method_frame->isa(
            'Net::AMQP::Protocol::Queue::PurgeOk') )
    {
        warn "Unable to purge queue $queue_name";
        $self->{debug}
            and print "Purge response frame:\n" . Dumper($purge_resp) . "\n";
        return 0;
    }
    $self->{debug}
        and print "Purged "
        . $purge_resp->method_frame->{message_count}
        . " messages from the $queue_name queue\n";
    return 1;
}

sub delete_queue {
    my ( $self, $queue_name, $cust_delete_args ) = @_;

    unless ($queue_name) {
        warn "No queue given to delete";
        return;
    }
    $cust_delete_args ||= {};
    $cust_delete_args->{queue} = $queue_name;
    my $def_delete_args
        = Net::AMQP::Haiku::Properties::def_queue_delete_properties();
    my $delete_args = { %{$def_delete_args}, %{$cust_delete_args} };
    my $delete_queue_frame
        = Net::AMQP::Protocol::Queue::Delete->new( %{$delete_args} );
    $self->_send_frames($delete_queue_frame) or return;

    if ( !$self->_check_frame_response('Net::AMQP::Protocol::Queue::DeleteOk')
        )
    {
        return 0;
    }

    $self->{debug}
        and print "Queue $delete_args->{queue} has been deleted.\n";
    return 1;
}

sub halt_consumption {
    my ( $self, $consumer_tag ) = @_;

    $consumer_tag ||= $self->{consumer_tag};
    my $halt_consume_frame = Net::AMQP::Protocol::Basic::Cancel->new(
        consumer_tag => $consumer_tag,
        nowait       => $self->{nowait} );
    $self->_send_frames($halt_consume_frame) or return;

    if ( !$self->_check_frame_response('Net::AMQP::Protocol::Basic::CancelOk')
        )
    {
        warn
            "Unable to stop consumer on queue $self->{queue} with tag $consumer_tag";
        return 0;
    }
    $self->{debug}
        and print
        "Consumer with tag $consumer_tag on $self->{queue} has stopped.\n";
    $self->{consumer_tag} = DEFAULT_CONSUMER_TAG;
    return 1;
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
    my ( $self, $resp_len ) = @_;

    $resp_len ||= DEFAULT_RECV_LEN;

    my ( $data, $data_len ) = $self->_read_socket($resp_len);

    unless ($data) {
        $data .= $self->_read_socket($resp_len) or return;
    }
    my ( $header, $body, $footer, $payload_size );

    ( $header, $payload_size, $data ) = unpack_data_header($data) or return;
    ( $body, $data ) = unpack_data_body( $data, $payload_size ) or return;

    # Do we have more to read?
    ( $body, $data ) = $self->_has_more_data( $body, $data, $payload_size );
    ( $footer, $data ) = unpack_data_footer($data) or return;

    my $full_msg = $header . $body . $footer;
    return ( $full_msg, $data );
}

sub _has_more_data {
    my ( $self, $body, $data, $payload_size ) = @_;
    unless ( ( $data || $body ) && $payload_size ) {
        return ( $body, $data );
    }
    my $tmp_bod;
    if ( length($body) < $payload_size || length $data == 0 ) {

        # remaining size should be payload + footer + what we currently have
        my $rem_len = $payload_size + _FOOTER_LENGTH - length($body);
        while ( $rem_len > 0 ) {
            $self->{debug} and print "Getting $rem_len chars more of data\n";
            my ( $chunk, $chunk_len ) = $self->_read_socket($rem_len)
                or return;
            $rem_len -= $chunk_len;
            $data .= $chunk;
        }
        # get the body using the size we want - what we currently have
        ( $tmp_bod, $data )
            = unpack_data_body( $data, $payload_size - length($body) )
            or return;
        # append the data we got to the body
        $body .= $tmp_bod;
    }
    return ( $body, $data );
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
    $length = _HEADER_LENGTH + _FOOTER_LENGTH if ( !defined($length) );

    $self->_set_recv_timeout();
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

sub _check_frame_response {
    my ( $self, $response ) = @_;

    unless ($response) {
        warn "No response frame given to " . ( caller(0) )[3];
        return;
    }
    my ($frame) = $self->_recv_frames();

    if ( !UNIVERSAL::isa( $frame, 'Net::AMQP::Frame::Method' ) ) {
        warn "Response frame is not a valid Net::AMQP::Frame::Method class:\n"
            . Dumper($frame) . "\n";
        return;
    }

    if ( !$frame->method_frame->isa($response) ) {
        print STDERR "Response frame is not of expected response "
            . $response . '.'
            . (
            ( defined( $frame->method_frame->{reply_text} ) )
            ? 'Error: ' . $frame->method_frame->{reply_text}
            : '' );
        $self->{debug}
            and print STDERR "Got response:\n" . Dumper($frame) . "\n";
        return 0;
    }

    $self->{debug}
        and print "Frame is of expected response $response\n"
        . Dumper($frame) . "\n";
    return 1;
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

=head1 EXPORT

NAME
VERSION

=head1 PUBLIC CLASS METHODS
    

=head2 B<new>

    Creates a new instance of the Net::AMQP::Haiku Object
    
    At a minimum, it expects the host name, and path to the AMQP spec file
    
    A list of configurable options are as follows:
    
    host            - the name of the AMQP server
    proto           - the protocol used
    port            - the port to connect to
    vhost           - the name of the virtual host
    username        - the name of the user to authenticate to the server as
    password        - the corresponding password
    locale          - locale that the client wants to use
    channel         - the channel id to use
    auth_mechanism  - the authentication mechanism that will be used
                        by the client
    spec_file       - the path to the spec file to use
    debug           - debugging flag
    timeout         - connection timeout for establishing initial socket
    
    Note that queue, exchange, exchange_type, routing_key should be set
    using their corresponding methods.
    
    The method is expected to die if it doesn't find the spec file on the path
    given. 
    
    This method returns the new instance of the Net::AMQP::Haiku object
    
=head2 B<connect>

    Opens a connection to the AMQP server. It takes 
    

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
