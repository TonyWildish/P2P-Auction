#!/usr/bin/env perl -w
use strict;
use Getopt::Long qw / :config pass_through/;
use Data::Dumper;

# sub POE::Kernel::TRACE_DEFAULT  () { 1 }
# sub POE::Kernel::TRACE_EVENTS   () { 1 }
# sub POE::Kernel::TRACE_SESSIONS () { 1 }
# sub POE::Kernel::TRACE_DESTROY () { 1 }
# sub POE::Kernel::TRACE_REFCNT () { 1 }

use PSP::Util;
use PSP::Auctioneer;
use PSP::Player;

my (%args,$auctioneer,$player,@players,%players);

GetOptions(
    "help"      => \$args{help},
    "verbose"   => \$args{verbose},
    "debug"     => \$args{debug},
    "test"      => \$args{test}  ,
    "config=s"  => \$args{config},
    "log=s"     => \$args{log},
    "poetrace"  => \$args{poe_trace},
    "poedebug"  => \$args{poe_debug},
    "player=s@" => \@players,
    );

sub usage {
  die <<EOF;

  Usage:  {options}

where

  options are:
  --help, --verbose, --debug are all obvious
  --config <string>   specifies a config file
  --log <string>      specifies a logfile

  --player <string>   name the players! Can (should!) be multiple

EOF
}
$args{help} && usage();

if ( ! scalar @players ) {
  die "No players? No dice!\n";
}

$auctioneer = new PSP::Auctioneer( %args );
foreach $player ( @players ) {
  $players{$player} = new PSP::Player( %args, Me => $player );
}

POE::Kernel->run();
print "All done, outta here...\n";
