use 5.008008;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME           => 'Net::AMQP::Haiku',
    VERSION_FROM   => 'lib/Net/AMQP/Haiku.pm',
    BUILD_REQUIRES => { 'Net::AMQP' => 0.02 },
    PREREQ_PM      => { 'Net::AMQP' => 0.02, Test::Exception => 0 },
    PREREQ_FATAL   => 'TRUE',
    (   $] >= 5.005
        ?    ## Add these new keywords supported since 5.005
            (
            ABSTRACT_FROM =>
                'lib/Net/AMQP/Haiku.pm',    # retrieve abstract from module
            AUTHOR => 'Rebs Guarina <rebs.guarina@gmail.com>' )
        : () ), );
