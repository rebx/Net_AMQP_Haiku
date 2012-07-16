
#########################

use strict;
use File::Spec;
use Test::More 'tests' => 35;
use Test::Exception;
use YAML qw(LoadFile);
my $name    = 'Net::AMQP::Haiku';
my @methods = qw(spec_file channel _load_spec_file _set_channel
    _connect_sock _parse_args connect set_queue open_channel send close);

my @tuning_params = qw(channel_max frame_max heartbeat);

BEGIN {
    use FindBin qw($Bin);
    use lib "$Bin/../lib";
    use Net::AMQP::Haiku;
    use_ok('Net::AMQP::Haiku');
}

require_ok('Net::AMQP::Haiku');
can_ok( 'Net::AMQP::Haiku', @methods );

#########################

my $test_conf_file = File::Spec->join( $Bin, 'test_conf.yaml' );
my $test_conf_hash = LoadFile($test_conf_file)
    or die "Unable to load test config at $test_conf_file: $!\n";
my $debug         = $test_conf_hash->{debug};
my $host          = $test_conf_hash->{host};
my $port          = $test_conf_hash->{port};
my $queue         = $test_conf_hash->{queue};
my $msg_send      = $test_conf_hash->{test_message};
my $routing_key   = $test_conf_hash->{routing_key};
my $exchange      = $test_conf_hash->{exchange};
my $exchange_type = $test_conf_hash->{exchange_type};
my $reply_to      = $test_conf_hash->{reply_to};
my ( $msg_recv, $uuid );

my $amqp_spec_file = File::Spec->join( $Bin, 'amqp0-8.xml' );
my $t;
ok( $t = Net::AMQP::Haiku->new(), "test new instance of $name" );
dies_ok { $t->spec_file('/foo/bar/baz.spec') }
'instance dies when spec file does not exist';
my $f = Net::AMQP::Haiku->new(
    { host => $host, spec_file => $amqp_spec_file, debug => $debug } );
ok( $f->connect(), "test connect to $host:$port" );
isnt( $f->{connection}, undef, "test socket is not undef" );
ok( $f->{connection}->isa('IO::Socket::INET'),
    "test socket is an instance of IO::Socket::INET" );
is( $f->{is_connected}, 1, "test is_connected flag is true" );
isnt( $f->{tuning_parameters}->{channel_max},
    undef, "test tuning parameter channel_max is defined" );
isnt( $f->{tuning_parameters}->{frame_max},
    undef, "test tuning parameter frame_max is defined" );
isnt( $f->{tuning_parameters}->{heartbeat},
    undef, "test tuning parameter heartbeat is defined" );

ok( $f->open_channel(), "test open channel" );

ok( $f->set_queue($queue), "test set queue to $queue" );
is( $f->{queue}, $queue, "test queue attribute is set to $queue" );
ok( $f->delete_queue($queue), "test delete queue $queue" );
ok( $f->set_queue(
        $queue, { durable => 0, auto_delete => 0, exclusive => 0 } ),
    "test set queue to $queue with extra attributes" );
is( $f->{queue}, $queue, "test queue attribute is set to $queue" );
ok( $f->set_exchange(
        $exchange,
        {   type        => $exchange_type,
            durable     => 0,
            auto_delete => 0,
            internal    => 0
        } ),
    "test set exchange $exchange type $exchange_type" );
ok( $f->bind_queue(
        {   queue       => $queue,
            routing_key => $routing_key,
            exchange    => $exchange
        } ),
    "test bind exchange $exchange to queue $queue with routing key $routing_key"
);

ok( $f->send($msg_send), "test send message to server" );
ok( $msg_recv = $f->receive($queue), "Test get message on queue $queue" );
is( "$msg_recv", "$msg_send", "Test got the ping message $msg_send" );
ok( $f->send( $msg_send, $queue, { reply_to => $reply_to } ),
    "Test send using reply_to $reply_to" );
ok( $msg_recv = $f->get( $queue, { reply_to => $reply_to } ),
    "Test get using reply_to $reply_to" );
is( "$msg_recv", "$msg_send", "Test got the ping message $msg_send" );
$uuid = `uuidgen`;
chomp($uuid);
undef $msg_recv;
ok( $f->send(
        $msg_send,
        $queue,
        {   reply_to    => $uuid,
            exchange    => $exchange,
            routing_key => $routing_key
        } ),
    "Test send using reply_to $uuid routing_key $routing_key" );
ok( $msg_recv = $f->get(
        $queue,
        {   reply_to    => $uuid,
            exchange    => $exchange,
            routing_key => $routing_key
        } ),
    "Test get using reply_to $uuid  routing_key $routing_key" );
is( "$msg_recv", "$msg_send", "Test got the ping message $msg_send" );

undef $msg_recv;
my $long_msg = (split(//, $msg_send))[1] x ($f->{tuning_parameters}->{frame_max} * 2);
my $len_long_msg = length($long_msg);
ok($f->send($long_msg), "test send long message of length " . $len_long_msg );
#$f->debug(1);
ok($msg_recv = $f->get($queue), "test get long message of length $len_long_msg" );
#ok($f->send($long_msg, {reply_to=> $uuid, exchange=> $exchange, routing_key => $routing_key}), "test send long message of length " . $len_long_msg );
#ok($msg_recv = $f->get($queue, {reply_to=> $uuid, exchange=> $exchange, routing_key => $routing_key}), "test get long message of length $len_long_msg" );
#$f->debug(0);
is (length($msg_recv), $len_long_msg, "test long message is of equal size");
#is ($msg_recv, $long_msg, "test long message is equal");
ok( $f->purge_queue($queue),  "Test purge queue $queue" );
ok( $f->delete_queue($queue), "test delete queue $queue" );
ok( $f->close(),              "test close connection properly" );

done_testing();
