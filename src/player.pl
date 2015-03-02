#!/usr/bin/env perl -w
use strict;
use Getopt::Long qw / :config pass_through/;
use Data::Dumper;
use PSP::Util;
use PSP::Player;

my (%args);

GetOptions(
    "help"      => \$args{help},
    "verbose"   => \$args{verbose},
    "debug"     => \$args{debug},
    "config=s"  => \$args{config},
    "log=s"     => \$args{log},
    "name=s"    => \$args{me},  # override the default name!
    );

sub usage {
  die <<EOF;

  Usage:  {options}

where

  options are:
  --help, --verbose, --debug are all obvious
  --config <string>   specifies a config file
  --log <string>      specifies a logfile

EOF
}
$args{help} && usage();

my $player = new PSP::Player( %args, @ARGV );
POE::Kernel->run();
print "All done, outta here...\n";