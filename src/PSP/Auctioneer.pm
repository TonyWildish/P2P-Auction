package PSP::Auctioneer;
use strict;
use warnings;

use HTTP::Status qw / :constants / ;
use base 'PSP::Util', 'PSP::Session';
use PSP::Listener;
use POE;
use JSON::XS;

use Data::Dumper;
$Data::Dumper::Terse=1;
$Data::Dumper::Indent=0;

# Make the code more readable with named constants...
use constant QUANTITY   => 0;
use constant PRICE      => 1;
use constant PLAYER     => 2;
use constant ALLOCATION => 3;
use constant COST       => 4;
# use constant TIMEOUT  => 2;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my ($self,$help,%params,%args,%pLower);
  %args = @_;

  %params = (
          Me            => __PACKAGE__,
          Config        => undef,
          Log           => undef,
          Verbose       => 0,
          Debug         => 0,
          Test          => undef,
          Pidfile       => undef,
          ConfigPoll    => 3,

#         Manage the bidding machinery
          CurrentPort   => 0,
          Port          => 3141,
          Listening     => 0,
          HandlerNames  => [
            'hello',
            'goodbye',
            'bid',
          ],

#         Parameters of the auction
          EqTimeout      =>  15, # How long with no bids before declaring equilibrium?
          Epsilon        =>   5, # bid-fee
          Q              => 100, # How much of whatever I'm selling
          TimeoutBids    =>   1, # Wait to gather more bids after one is received
          TimeoutAuction =>   3, # How long with no bids to declare auction over?
        );

  $self = \%params;
  map { $pLower{lc $_} = $_ } keys %params;

  bless $self, $class;
  foreach ( keys %args ) {
    if ( exists $pLower{lc $_} ) {
      $self->{$pLower{lc $_}} = delete $args{$_};
    }
  }
  map { $self->{$_} = $args{$_} if $args{$_} } keys %args;
  die "No --config file specified!\n" unless defined $self->{Config};
  $self->ReadConfig($self->{Me},$self->{Config});

  map { $self->{Handlers}{$_} = 1 } @{$self->{HandlerNames}};

  if ( $self->{Log} && ! $self->{Pidfile} ) {
    $self->{Pidfile} = $self->{Log};
    $self->{Pidfile} =~ s%.log$%%;
    $self->{Pidfile} .= '.pid';
  }
  $self->daemon() if $self->{Log};

#   POE::Session->create(
#     object_states => [
#       $self => {
#         _start          => '_start',
#         _stop           => '_stop',
#         _child          => '_child',
#         _default        => '_default',
#         re_read_config  => 're_read_config',
#         ContentHandler  => 'ContentHandler',
#         ErrorHandler    => 'ErrorHandler',

#         SendOffer       => 'SendOffer',

# # The FSM for the auction
# # The machine starts at Idle. When a bid comes in it switches to
# # CollectingBids for a few seconds. Then it goes to AuctionStarted.
# # In AuctionStarted it runs the auction and sends allocations,
# # re-running and sending if new bids come in within a certain
# # time-interval. After that it goes to AuctionEnded, which
# # does the final house-keeping, then back to Idle again.
# #
# # In CollectingBids and AuctionStarted, incoming bids are added to
# # the next or current auction. Any new bid will trigger a re-run of
# # the auction with the existing bid-set, including bids from players
# # who haven't re-bid once the auction has started.
# #
# # In AuctionStarted, the auctioneer sends 'offer' events to players.
# # Once the auction is complete, it sends a final 'allocation' event.
# #
# # In AuctionEnded, the final allocations are made, and the
# # existing set of bids are removed.
# #
# # Legal transitions are:
# # Idle -> CollectingBids -> AuctionStarted -> AuctionEnded -> Idle
#         CollectingBids  => 'CollectingBids',
#         AuctionStarted  => 'AuctionStarted',
#         AuctionEnded    => 'AuctionEnded',
#         Idle            => 'Idle',
#       },
#     ],
#   );

  return $self;
}

# (re-)initialisation
# sub start {
#   my $self = shift;
#   $self->Idle();

#   $self->test() if $self->{Test};
# }

sub players {
  my $self = shift;
  my @players = keys %{$self->{bids}};
  return \@players;
}

# sub PostReadConfig {
#   my $self = shift;
#   return if $self->{Port} == $self->{CurrentPort};
#   if ( $self->{Listening} ) {
#     $self->Log('Port has changed, stop/start listening');
#     $self->StopListening();
#   }
#   $self->{CurrentPort} = $self->{Port};
#   $self->StartListening();
# }

# # handle interaction with players
# sub hello {
#   my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];

#   defined($args->{url}) or die "No url defined in message\n";
#   defined($args->{player}) or die "No player defined in message\n";
#   $self->{urls}{$args->{player}} = $args->{url};
#   $self->{players}{$args->{url}} = $args->{player};
#   $self->Log('Hello from ',$args->{player},' (',$args->{url},')');
# # Send Auction parameters: Q, Epsilon, IdleTimeout...
# }

# sub goodbye {
#   my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];
#   $self->Log('Goodbye handler...');
# }

# sub bid {
#   my ($self,$kernel,$args,$player) = @_[ OBJECT, KERNEL, ARG0, ARG1 ];
#   my ($p,$q,$t);

#   defined($p = $args->{p}) or die "No price defined in bid\n";
#   defined($q = $args->{q}) or die "No quantity defined in bid\n";
#   $self->Log("Bid from $player: (q=$q,p=$p)");

#   $t = time();
#   $self->RunPSP($player,[$q,$p,$t]);
#   # $self->{bids}{$player} = [$q,$p,$t]; # Quantity, Price, Timeout...
#   $self->{LastBidTime} = $t;
#   # $kernel->yield('CollectingBids') if $self->{State} eq 'Idle';
# }

# # handle my own FSM
# sub Idle {
#   my ($self,$kernel) = @_[ OBJECT, KERNEL ];
#   $self->Log('State: Idle');
#   $self->{State} = 'Idle';
#   $self->{AuctionEndTime} = 0;
#   delete $self->{bids};
#   delete $self->{allocation};

# # TW
#   print "\n";
# }

# sub CollectingBids {
# #   my ($self,$kernel) = @_[ OBJECT, KERNEL ];
# #   $self->Log('State: CollectingBids');
# #   $self->{State} = 'CollectingBids';
# #   $kernel->delay_set('AuctionStarted',$self->{TimeoutBids});
# }

# sub AuctionStarted {
# #   my ($self,$kernel) = @_[ OBJECT, KERNEL ];
# #   my ($player,$bid);
# #   $self->Log('State: AuctionStarted');
# #   $self->{State} = 'AuctionStarted';

# #   if ( $self->{bids} ) {
# #     $self->RunPSP();
# #     $kernel->yield('SendOffer','offer');
# #   }

# # # Set timer for switching to AuctionEnded state
# #   if ( ! $self->{AuctionRunning} ) {
# #     $self->{AuctionRunning} = 1;
# #     $kernel->delay_set('AuctionEnded',$self->{TimeoutAuction});
# #   }
# }

# sub AuctionEnded {
# # # Poll to see if the auction should be ended, or re-run
# #   my ($self,$kernel) = @_[ OBJECT, KERNEL ];

# #   if ( $self->{LastBidTime} >= $self->{LastRunTime} ) {
# #     $self->RunPSP();
# #     $kernel->yield('SendOffer','offer');
# #     $kernel->delay_set('AuctionEnded',2);
# #     return;
# #   }

# #   my $delta_t = time - $self->{LastRunTime};
# #   if ( $delta_t < $self->{TimeoutAuction} ) {
# #     $self->Log('State: AuctionEnded (no)');
# #     $kernel->delay_set('AuctionEnded',2);
# #   } else {
# #     $self->Log('State: AuctionEnded (yes)');
# #     $kernel->yield('SendOffer','allocation');
# #     $kernel->yield('Idle');
# #     $self->{State} = 'AuctionEnded';
# #     $self->{AuctionRunning} = 0;
# #   }
# }

# sub SendOffer {
#   my ($self,$kernel,$api) = @_[ OBJECT, KERNEL, ARG0 ];
#   my ($allocation,$cost,$Api,$player);
#   $Api = ucfirst $api;
#   foreach $player ( @{$self->players()} ) {
#     next unless defined($self->{allocation}{$player} );
#     $allocation = $self->{allocation}{$player}[QUANTITY];
#     $cost       = $self->{allocation}{$player}[PRICE];
#     $self->Dbg($Api,': ',$player,' (a=',$allocation,',c=',$cost,')');
#     my $response = $self->get({
#           api    => $api,
#           data   => $self->{allocation},
#           target => $self->{urls}{$player} . $player . '/'
#         });
#     $self->Log($Api,': ',$player,', (a=',$allocation,',c=',$cost,') OK');
#   }
# }

# # sub Q_ {
# # # $y is the bid-price being compared to
# # # $s is the player omitted from this strategy
# #   my ($self,$y,$s) = @_;
# #   my ($Q_,$player,$bid);
# #   $Q_ = $self->{Q};

# # # redundant...
# #   if ( $y < 0 ) { die "Q_ not defined for negative y ($y,$s)\n"; }  

# #   foreach $player ( @{$self->players()} ) {
# #     # $bid = $self->{bids}{$player};
# #     # print "  Q_($y,$s): player=$player, q=",$bid->[QUANTITY]," p=",$bid->[PRICE],", Q_=$Q_\n" if $self->{Test};

# #     next if $player eq $s; # This means we loop over 's(-i)'
# #     $bid = $self->{bids}{$player};
# #     next if $bid->[PRICE] < $y;
# #     $Q_ -= $bid->[QUANTITY];
# #     # print "  Q_ = $Q_\n" if $self->{Test};
# #   }
# #   if ( $Q_ < 0 ) { $Q_ = 0; }
# #   return $Q_;
# # }

# # sub allocation {
# # # $i is the player, if any, under active consideration
# # # $s is the player omitted from this strategy
# #   my ($self,$i,$s) = @_;
# #   my ($allocation,$p_i,$q_i,$Q_i);
# #   print "Allocation: $i, $s\n";
# #   $p_i = 0;
# #   $p_i = $self->{bids}{$i}[PRICE] if $i;

# #   $q_i = $self->{bids}{$s}[QUANTITY];
# #   $Q_i = $self->Q_($p_i,$s);

# #   if ( $q_i < $Q_i ) { $allocation = $q_i; }
# #   else               { $allocation = $Q_i; }
# #   print "Q_i($i,$s) = $Q_i, q_i = $q_i, allocation = $allocation\n";
# #   return $allocation;
# # }

# # sub cost {
# #   my ($self,$i) = @_;
# #   my ($cost,$p_j,$player,$a0,$ai);

# #   $cost = 0;
# #   foreach $player ( @{$self->players()} ) {
# #     next if $player eq $i;
# #     print "Cost: $player, $i\n";
# #     $a0 = $self->allocation(      0,$i);
# #     $ai = $self->allocation($player,$i);
# #     $p_j = $self->{bids}{$player}[PRICE];
# #     $cost += $p_j * ($a0 - $ai );
# #     print "Player $i: a0=$a0, ai=$ai, p_j=$p_j, cost=$cost\n";
# #   }
# #   return $cost;
# # }

# # sub RunPSP {
# #   my $self = shift;
# #   my ($player,$bid,$allocation,$cost);
# # # Here I calculate the allocations!
# #   $self->Log('RunPSP!');
# #   $self->{LastRunTime} = time();

# #   foreach $player ( @{$self->players()} ) {
# #     next unless defined($bid = $self->{bids}{$player});
# #     $self->Dbg('Player ',$player,' delta_t=',$self->{LastRunTime}-$bid->[TIMEOUT]);
# #     next if ( $bid->[TIMEOUT] < $self->{LastRunTime} &&
# #               defined($self->{allocation}{$player} ) );
# #     print "\nRunPSP: $player\n";
# #     $allocation = $self->allocation($player,$player);
# #     $cost = $self->cost($player);
# #     $self->{allocation}{$player} = [$allocation, $cost+$self->{Epsilon}];
# #   }
# # }

# # sub test {
# #   my $self = shift;
# #   my ($i,$j);
# #   $self->{players} = [ "player1", "player2" ];

# # # A single player should get everything
# #   # $self->{bids} = { "player1" => [70, 7, 999_999_999_999 ], };
# #   # print "player1: q=",$self->{bids}{player1}[QUANTITY]," p=",$self->{bids}{player1}[PRICE],"\n";
# #   # print "min-price=",$self->{bids}{player1}[PRICE],", omit player1\n";
# #   # print ' Q_=',$self->Q_($self->{bids}{player1}[PRICE],'player1'),"\n\n";
# #   # print "\n";

# # # two bidders with same price: Q=(total - bid-of-other-player)
# #   # $self->{bids} = {
# #   #   "player1" => [60, 7, 999_999_999_999 ],
# #   #   "player2" => [70, 7, 999_999_999_999 ],
# #   # };
# #   $self->{bids} = {
# #     "player1" => [70, 7, 999_999_999_999 ],
# #     "player2" => [70, 8, 999_999_999_999 ],
# #   };

# #   foreach $i ( sort @{$self->{players}} ) {
# #     print "$i: q=",$self->{bids}{$i}[QUANTITY]," p=",$self->{bids}{$i}[PRICE],"\n";
# #   }
# #   print "\n";
# #   print "min-price=",$self->{bids}{player1}[PRICE],", omit player2\n";
# #   print ' Q_=',$self->Q_($self->{bids}{player1}[PRICE],'player2'),"\n\n";
# #   print "\n";
# #   print "min-price=",$self->{bids}{player2}[PRICE],", omit player1\n";
# #   print ' Q_=',$self->Q_($self->{bids}{player2}[PRICE],'player1'),"\n\n";

# #   print "allocation(player1,player2) = ",$self->allocation('player1','player2'),"\n";
# #   print "allocation(player2,player1) = ",$self->allocation('player2','player1'),"\n\n";

# # # Phase two...
# #   exit 0;
# #   $self->{bids} = {
# #     "player1" => [89, 6, 999_999_999_999 ],
# #     "player2" => [70, 7, 999_999_999_999 ],
# #   };

# #   foreach $i ( sort @{$self->{players}} ) {
# #     print "$i: q=",$self->{bids}{$i}[QUANTITY]," p=",$self->{bids}{$i}[PRICE],"\n";
# #   }
# #   print "\n";
# #   foreach $i ( sort @{$self->{players}} ) {
# #     for ( $j=5; $j<=8; $j++ ) {
# #       print "min-price=$j, omit player '$i'\n";
# #       print ' Q_=',$self->Q_($j,$i),"\n\n";
# #     }
# #   }

# #   print "allocation(player1,player2) = ",$self->allocation('player1','player2'),"\n\n";
# #   print "allocation(player2,player1) = ",$self->allocation('player2','player1'),"\n\n";
# #   print "allocation(0,player2) = ",$self->allocation(0,'player1'),"\n\n";
# #   print "allocation(0,player2) = ",$self->allocation(0,'player2'),"\n\n";

# #   exit 0;
# # }

sub test {
  my $self = shift;
  $DB::single=1;
  $self->RunPSP([70,3,'player1']); $self->showAllocations();
  $self->RunPSP([60,6,'player2']); $self->showAllocations();
  $self->RunPSP([50,4,'player3']); $self->showAllocations();
  $self->RunPSP([40,5,'player4']); $self->showAllocations();
  $self->RunPSP([55,9,'player5']); $self->showAllocations();
  $self->RunPSP([80,3,'player6']); $self->showAllocations();

  exit 0;
}

sub min {
  my ($x,$y) = @_;
  return $x if $x < $y;
  return $y;
}

sub showAllocations {
  my $self = shift;
  foreach my $player ( sort @{$self->players()} ) {
    my $bid = $self->{bids}{$player};
    print 'Allocation for ',$bid->[PLAYER],': ',$bid->[ALLOCATION],"\n";
  }
  print "\n";
}

sub RunPSP {
  my ($self,$newbid) = @_;
  my ($player,$bids,@bids,$Qi,$ai,$ci,$bid);

  $self->{bids} = {} unless defined $self->{bids};

  $player = $newbid->[PLAYER];
  print "RunPSP: New bid: Player=$player, bid=[",$newbid->[QUANTITY],',',$newbid->[PRICE],"]\n";

# Remove any previous bid by this same player, we will be replacing it...
  $bids = $self->{bids};
  # delete $bids->{$player} if exists( $bids->{$player} );
  $bids->{$player} = $newbid;

# Sort the bids by price-order
  @bids = sort { $a->[PRICE] <=> $b->[PRICE] }  values %{$bids};
  print "Sorted bids:\n";
  print map { '  [' . join(', ',@{$_}) . "]\n" } @bids;
  print "\n";

  $Qi = $self->{Q};
  $ai = $ci = 0;

  foreach $bid ( @bids ) {
    next if $bid->[PLAYER] eq $newbid->[PLAYER];
    if ( $bid->[PRICE] >= $newbid->[PRICE] ) {
      $Qi -= $bid->[QUANTITY];
      if ( $Qi <= 0 ) {
        $Qi = 0;
        last;
      }
    }
  }

# $newbid->[ALLOCATION] is 'A' in the algorithm as described in the patent
  $newbid->[ALLOCATION] = $ai = min($Qi,$newbid->[QUANTITY]);
  print "Allocation for new player = $ai = min($Qi,",$newbid->[QUANTITY],")\n";

# Now the newbid has its quantity allocated. Bids with price less than the price
# of the newbid still have their original allocations, which need to be adjusted.
# The cost to all players below the newbid also need to be corrected.

# First, calculate the new allocations for players who bid less than newbid...
  $Qi = $self->{Q};
  foreach $bid ( @bids ) {
    if ( $bid->[PRICE] >= $newbid->[PRICE] ) {
      $Qi -= $bid->[ALLOCATION];
      if ( $Qi < 0 ) { die " Qi = $Qi, how can this be???\n"; }
    } else {
      print "Total not yet allocated: $Qi\n";
      $bid->[ALLOCATION] = min($Qi,$bid->[QUANTITY]);
    }
  }



#-------------------------------------------
  # $allocations = {};
  # @players = @{$self->players()};
}

1;