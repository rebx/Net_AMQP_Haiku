
#########################

use strict;
use File::Spec;
use Test::More 'no_plan';
use Test::Exception;
use YAML qw(LoadFile);
my $name = 'Net::AMQP::Haiku';

BEGIN {
    use FindBin qw($Bin);
    use lib "$Bin/../lib";
    use Net::AMQP::Haiku;
    use_ok('Net::AMQP::Haiku');
    use Net::AMQP::Haiku::Constants qw(DEFAULT_CONSUMER_TAG);
}
my $test_conf_file = File::Spec->join( $Bin, 'test_conf.yaml' );
my $test_conf_hash = LoadFile($test_conf_file)
    or die "Unable to load test config at $test_conf_file: $!\n";
my $debug          = $test_conf_hash->{debug};
my $host           = $test_conf_hash->{host};
my $port           = $test_conf_hash->{port};
my $queue          = $test_conf_hash->{queue};
my $exchange       = $test_conf_hash->{exchange};
my $exchange_type  = $test_conf_hash->{exchange_type};
my $routing_key    = $test_conf_hash->{routing_key};
my $amqp_spec_file = File::Spec->join( $Bin, 'amqp0-8.xml' );
my $test_msg       = $test_conf_hash->{test_message};
my $consumer_tag   = $test_conf_hash->{consumer_tag};
my $num_queue      = $test_conf_hash->{num_messages};
my $recv_msg;

require_ok('Net::AMQP::Haiku');

my $p = Net::AMQP::Haiku->new(
    { host => $host, spec_file => $amqp_spec_file, debug => $debug } );
ok( $p->open_channel(),          "test open channel" );
ok( $p->set_queue($queue),       "test set queue to $queue" );
ok( $p->set_exchange($exchange), 'test set exchange to ' . $exchange );
ok( $p->bind_queue(
        {   queue       => $queue,
            exchange    => $exchange,
            routing_key => $routing_key
        } ),
    "Test bind to queue $queue" );
ok( $p->consume_queue($queue), "Test consume to $queue" );
isnt( $p->{consumer_tag}, DEFAULT_CONSUMER_TAG,
    "test consumer tag is not the same as the default one" );
ok( $p->halt_consumption(),
    "test stop consuming from $queue with tag $p->{consumer_tag}" );
ok( $p->consume_queue( $queue, { consumer_tag => $consumer_tag } ),
    "Test consume to $queue" );
isnt( $p->{consumer_tag}, DEFAULT_CONSUMER_TAG,
    "test consumer tag is not the same as the default one" );
is ($p->{consumer_tag}, $consumer_tag, "Test consumer tag is $consumer_tag");

ok( $p->purge_queue($queue), "test purge queue $queue before consuming" );

for ( my $i = 1; $i <= $num_queue; $i++ ) {
    $recv_msg = '';
    #$test_msg = $test_msg x ($p->{tuning_parameters}->{frame_max} * $i);
    ok( $recv_msg = $p->nom( $queue, { consumer_tag => $consumer_tag } ),
        "test consume $queue $i of $num_queue" );
    is( $recv_msg, $test_msg,
        "test consumed message in queue $queue is $test_msg" );
}
ok( $p->halt_consumption(),
    "test stop consuming from $queue with tag $p->{consumer_tag}" );
ok( $p->close(), "test close connection properly" );
