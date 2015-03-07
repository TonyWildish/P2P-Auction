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

  POE::Session->create(
    object_states => [
      $self => {
        _start          => '_start',
        _stop           => '_stop',
        _child          => '_child',
        _default        => '_default',
        re_read_config  => 're_read_config',
        ContentHandler  => 'ContentHandler',
        ErrorHandler    => 'ErrorHandler',

        SendOffer       => 'SendOffer',

# The FSM for the auction
# The machine starts at Idle. When a bid comes in it switches to
# CollectingBids for a few seconds. Then it goes to AuctionStarted.
# In AuctionStarted it runs the auction and sends allocations,
# re-running and sending if new bids come in within a certain
# time-interval. After that it goes to AuctionEnded, which
# does the final house-keeping, then back to Idle again.
#
# In CollectingBids and AuctionStarted, incoming bids are added to
# the next or current auction. Any new bid will trigger a re-run of
# the auction with the existing bid-set, including bids from players
# who haven't re-bid once the auction has started.
#
# In AuctionStarted, the auctioneer sends 'offer' events to players.
# Once the auction is complete, it sends a final 'allocation' event.
#
# In AuctionEnded, the final allocations are made, and the
# existing set of bids are removed.
#
# Legal transitions are:
# Idle -> CollectingBids -> AuctionStarted -> AuctionEnded -> Idle
        # CollectingBids  => 'CollectingBids',
        # AuctionStarted  => 'AuctionStarted',
        # AuctionEnded    => 'AuctionEnded',
        # Idle            => 'Idle',
      },
    ],
  );

  return $self;
}

# (re-)initialisation
sub start {
  my $self = shift;
  $self->Idle();

  $self->test() if $self->{Test};
}

sub PostReadConfig {
  my $self = shift;
  return if $self->{Port} == $self->{CurrentPort};
  if ( $self->{Listening} ) {
    $self->Log('Port has changed, stop/start listening');
    $self->StopListening();
  }
  $self->{CurrentPort} = $self->{Port};
  $self->StartListening();
}

# handle interaction with players
sub hello {
  my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];

  defined($args->{url}) or die "No url defined in message\n";
  defined($args->{player}) or die "No player defined in message\n";
  $self->{urls}{$args->{player}} = $args->{url};
  $self->{players}{$args->{url}} = $args->{player};
  $self->Log('Hello from ',$args->{player},' (',$args->{url},')');
# Send Auction parameters: Q, Epsilon, IdleTimeout...
}

sub goodbye {
  my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];
  $self->Log('Goodbye handler...');
}

sub bid {
  my ($self,$kernel,$args,$player) = @_[ OBJECT, KERNEL, ARG0, ARG1 ];
  my ($p,$q,$t);

  defined($p = $args->{p}) or die "No price defined in bid\n";
  defined($q = $args->{q}) or die "No quantity defined in bid\n";
  $self->Log("Bid from $player: (q=$q,p=$p)");

  $self->RunPSP([$q,$p,$player]);
  $self->showAuction();
  $kernel->yield('SendOffer','offer');
  # $self->{bids}{$player} = [$q,$p,$t]; # Quantity, Price, Timeout...
  # $self->{LastBidTime} = $t;
  # $kernel->yield('CollectingBids') if $self->{State} eq 'Idle';
}

# handle my own FSM
sub Idle {
  my ($self,$kernel) = @_[ OBJECT, KERNEL ];
  $self->Log('State: Idle');
  $self->{State} = 'Idle';
  $self->{AuctionEndTime} = 0;
  delete $self->{bids};
  delete $self->{allocation};
}

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

sub SendOffer {
  my ($self,$kernel,$api) = @_[ OBJECT, KERNEL, ARG0 ];
  my ($allocation,$Api,$player);
  $Api = ucfirst $api;
  $DB::single=1;
  foreach $player ( keys %{$self->{bids}} ) {
    $allocation->{$player} = {
      q => $self->{bids}{$player}[QUANTITY],
      c => $self->{bids}{$player}[COST]
    };
  }
  foreach $player ( sort keys %{$allocation} ) {
    $self->Dbg($Api,': ',$player,
      ' (a=',$allocation->{$player}{q},
      ',c=', $allocation->{$player}{c},
      ')'
    );
    my $response = $self->get({
          api    => $api,
          data   => $allocation,
          target => $self->{urls}{$player} . $player . '/'
        });
    $self->Log($Api,': ',$player,
      ' (a=',$allocation->{$player}{q},
      ',c=', $allocation->{$player}{c},
      ') OK'
    );
  }
}

sub min {
  my ($x,$y) = @_;
  return $x if $x < $y;
  return $y;
}

sub showAuction {
  my $self = shift;
  my @ordered = map {
      $_->[PLAYER]
    } sort {
      $b->[PRICE]      <=> $a->[PRICE]      ||
      $b->[ALLOCATION] <=> $a->[ALLOCATION] ||
      $b->[QUANTITY]   <=> $a->[QUANTITY]
    } values %{$self->{bids}};

  print " Player: Qty, Bid, Alloc, Cost\n";
  foreach my $player ( @ordered ) {
    my $bid = $self->{bids}{$player};
    print ' ',$bid->[PLAYER],': [',
      $bid->[QUANTITY], ', ',
      $bid->[PRICE], ', ',
      $bid->[ALLOCATION], ', ',
      (defined($bid->[COST]) ? $bid->[COST] : 'undef'),
      "]\n";
  }
  print "\n";
}

sub Allocations {
  my ($self,$bids,$omit) = @_;
  my ($bid_i,$bid_j,$Qi,$i,$j,$a);
  $omit = 0 unless defined $omit;

  for ( $i=0; $i<scalar @{$bids}; $i++ ) {
    $bid_i = $bids->[$i];
    $a->{$bid_i->[PLAYER]} = 0;
    next if ( $omit && $omit eq $bid_i->[PLAYER] );

    $Qi = $self->{Q};
    for ( $j=0; $j<scalar @{$bids}; $j++ ) {
      next if $i == $j;
      $bid_j = $bids->[$j];
      last if $bid_j->[PRICE] < $bid_i->[PRICE];
      $Qi -= $bid_j->[QUANTITY];
      if ( $Qi <= 0 ) {
        $Qi = 0;
        last;
      }
    }
    $a->{$bid_i->[PLAYER]} = min($Qi,$bid_i->[QUANTITY]);
  }
  return $a;
}

sub RunPSP {
  my ($self,$newbid) = @_;
  my ($player,$bids,@bids,$Qi,$bid,$aj,$allocations);
  $self->{bids} = {} unless defined $self->{bids};
  $bids = $self->{bids};

  if ( $newbid ) {
    $player = $newbid->[PLAYER];
    print "RunPSP: New bid: Player=$player, bid=[",$newbid->[QUANTITY],',',$newbid->[PRICE],"]\n";
    $bids->{$player} = $newbid;
  }

# Sort the bids by descending price-order
  @bids = sort { $b->[PRICE] <=> $a->[PRICE] }  values %{$bids};
  if ( $self->{DEBUG} ) {
    print "Sorted bids:\n";
    print map { '  [' . join(', ',@{$_}) . "]\n" } @bids;
    print "\n";
  }

# Calculate the allocations for each player.
  $allocations = $self->Allocations(\@bids);
  map { $self->{bids}{$_}->[ALLOCATION] = $allocations->{$_} } keys %{$allocations};
  print 'Allocation for ',$player,' = ',$newbid->[ALLOCATION],"\n" if $newbid;

# Now the quantities are allocated for all bids I can calculate the cost.
  foreach $bid ( @bids ) {
    $allocations = $self->Allocations(\@bids,$bid->[PLAYER]); # omit players in turn
    $bid->[COST] = 0;
    foreach ( keys %{$allocations} ) {
      next if $_ eq $bid->[PLAYER];
      $bid->[COST] += $self->{bids}{$_}[PRICE] *
            ( $allocations->{$_} - $self->{bids}{$_}[ALLOCATION] );
    }
  }
}

sub test {
  my $self = shift;
  $DB::single=1;
  # $self->RunPSP([70,3,'player1']); $self->showAuction();
  # $self->RunPSP([60,6,'player2']); $self->showAuction();
  # $self->RunPSP([50,4,'player3']); $self->showAuction();
  # $self->RunPSP([40,5,'player4']); $self->showAuction();
  # $self->RunPSP([55,9,'player5']); $self->showAuction();
  # $self->RunPSP([80,3,'player6']); $self->showAuction();

# A single player should get everything
  # $self->RunPSP([70, 7, 'player1' ]); $self->showAuction();

# two bidders with same price not exceeding the total: cost=0
  # $self->{bids} = {
  #   "player1" => [70, 7, 'player1' ],
  #   "player2" => [30, 7, 'player2' ],
  # };
  # print " ==> expect cost=0 for both players\n";
  # $self->RunPSP(); $self->showAuction();

# two bidders with same price, exceeding the total: cost=0
  # $self->{bids} = {
  #   "player1" => [70, 4, 'player1' ],
  #   "player2" => [60, 4, 'player2' ],
  # };
  # print " ==> expect player1: (q=40,c=0), player2: (q=30,c=0)\n";
  # $self->RunPSP(); $self->showAuction();

# four bidders with same price, exceeding the total: cost=0
  # $self->{bids} = {
  #   "player1" => [30, 4, 'player1' ],
  #   "player2" => [40, 4, 'player2' ],
  #   "player3" => [50, 4, 'player3' ],
  #   "player4" => [60, 4, 'player4' ],
  # };
  # print " ==> expect (q=0,c=0) for all players\n";
  # $self->RunPSP(); $self->showAuction();

# four bidders, three with same price, exceeding the total:
  $self->{bids} = {
    "player1" => [15, 4, 'player1' ],
    "player2" => [25, 4, 'player2' ],
    "player3" => [35, 4, 'player3' ],
    "player4" => [45, 5, 'player4' ],
  };
  print " ==> expect player1(q=0,c=0), player2(q=5,c=20), player3(q=15,c=140), player4(q=45,c=220),\n";
  $self->RunPSP(); $self->showAuction();

  exit 0;
}

1;