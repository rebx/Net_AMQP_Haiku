# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl Net-AMQP-Haiku.t'

#########################

use strict;
use File::Spec;
use Test::More 'no_plan';
use Test::Exception;
use YAML qw(LoadFile);
my $name    = 'Net::AMQP::Haiku';
my @methods = qw(spec_file channel _load_spec_file _set_channel
    _connect_sock _parse_args connect set_queue open_channel send close);

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
my $debug    = $test_conf_hash->{debug};
my $host     = $test_conf_hash->{host};
my $port     = $test_conf_hash->{port};
my $queue    = $test_conf_hash->{queue};
my $msg_send = 'ohai!';

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

ok( $f->open_channel(),    "test open channel" );
ok( $f->set_queue($queue), "test set queue to $queue" );
ok( $f->send($msg_send),   "test send message to server" );
my $msg_recv = '';
ok( $msg_recv = $f->get($queue), "Test get message on queue $queue" );
is( $msg_recv, $msg_send, "Test got the ping message $msg_send" );
ok( $f->close(), "test close connection" );

#done_testing();
