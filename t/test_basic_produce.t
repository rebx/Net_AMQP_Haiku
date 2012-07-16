
#########################

use strict;
use File::Spec;
use Test::More 'tests' => 12;
use Test::Exception;
use YAML qw(LoadFile);
my $name = 'Net::AMQP::Haiku';

BEGIN {
    use FindBin qw($Bin);
    use lib "$Bin/../lib";
    use Net::AMQP::Haiku;
    use_ok('Net::AMQP::Haiku');
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

for ( my $i = 1; $i <= $num_queue; $i++ ) {
    #$test_msg = $test_msg x ($p->{tuning_parameters}->{frame_max} * $i);
    ok( $p->send($test_msg), "send message $test_msg $i of $num_queue" );
}

ok( $p->close(), "test close connection properly" );

done_testing();
