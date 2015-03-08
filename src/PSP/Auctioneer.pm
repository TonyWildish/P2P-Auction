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

  die "No --config file specified!\n" unless defined $args{config};
  $self->ReadConfig($self->{Me},$args{config});

  foreach ( keys %args ) {
    if ( exists $pLower{lc $_} ) {
      $self->{$pLower{lc $_}} = delete $args{$_};
    }
  }
  map { $self->{$_} = $args{$_} if $args{$_} } keys %args;

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

  if ( $self->{Test} ) {
    $self->test();
    exit 0;
  }
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
}

sub Allocations {
  my ($self,$bids,$omit) = @_;
  my ($bid_i,$bid_j,$Qi,$i,$j,$a,$b);

  if ( $omit ) {
    $b = [];
    foreach ( @{$bids} ) {
      if ( $_->[PLAYER] eq $omit ) {
        $a->{$_->[PLAYER] } = 0;
        next;
      }
      push @{$b}, $_;
    }
  } else {
    $b = $bids;
  }

  for ( $i=0; $i<scalar @{$b}; $i++ ) {
    $bid_i = $b->[$i];
    $a->{$bid_i->[PLAYER]} = 0;

    $Qi = $self->{Q};
    for ( $j=0; $j<scalar @{$b}; $j++ ) {
      next if $i == $j;
      $bid_j = $b->[$j];
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
  if ( $self->{Debug} ) {
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
      next unless $bid->[ALLOCATION];
      $bid->[COST] += $self->{bids}{$_}[PRICE] *
            ( $allocations->{$_} - $self->{bids}{$_}[ALLOCATION] );
    }
  }
}

sub test {
  my $self = shift;

  # $self->RunPSP([70,3,'player1']); $self->showAuction();
  # $self->RunPSP([60,6,'player2']); $self->showAuction();
  # $self->RunPSP([50,4,'player3']); $self->showAuction();
  # $self->RunPSP([40,5,'player4']); $self->showAuction();
  # $self->RunPSP([55,9,'player5']); $self->showAuction();
  # $self->RunPSP([80,3,'player6']); $self->showAuction();

  print "1) 1 bidder, should get everything at no cost\n";
  $self->RunPSP([70, 7, 'player1' ]); $self->showAuction();
  $self->expect( {
      player1 => [ 70, 0 ],
    } );

  print "2) 2 bidders, not exceeding total Q\n";
  $self->{bids} = {
    "player1" => [70, 7, 'player1' ],
    "player2" => [30, 7, 'player2' ],
  };
  $self->RunPSP(); $self->showAuction();
  $self->expect( {
      player1 => [ 70, 0 ],
      player2 => [ 30, 0 ],
    } );

  print "3) 2 bidders, same price, exceeds total Q\n";
  $self->{bids} = {
    "player1" => [70, 4, 'player1' ],
    "player2" => [60, 4, 'player2' ],
  };
  $self->RunPSP(); $self->showAuction();
  $self->expect( {
      player1 => [ 40, 120 ],
      player2 => [ 30, 120 ],
    } );

  print "4) 4 bidders, same price, exceeds total Q\n";
  $self->{bids} = {
    "player1" => [20, 4, 'player1' ],
    "player2" => [30, 4, 'player2' ],
    "player3" => [40, 4, 'player3' ],
    "player4" => [50, 4, 'player4' ],
  };
  $self->RunPSP(); $self->showAuction();
  $self->expect( {
      player1 => [  0,   0 ],
      player2 => [  0,   0 ],
      player3 => [  0,   0 ],
      player4 => [ 10, 360 ],
    } );

  print "5) 4 bidders, same price, exceeds total Q\n";
  $self->{bids} = {
    "player1" => [30, 4, 'player1' ],
    "player2" => [40, 4, 'player2' ],
    "player3" => [50, 4, 'player3' ],
    "player4" => [60, 4, 'player4' ],
  };
  $self->RunPSP(); $self->showAuction();
  $self->expect( {
      player1 => [ 0, 0 ],
      player2 => [ 0, 0 ],
      player3 => [ 0, 0 ],
      player4 => [ 0, 0 ],
    } );

# four bidders, three with same price, exceeding the total:
  print "6) 4 bidders, 3 with same price, exceeds total Q\n";
  $self->{bids} = {
    "player1" => [15, 4, 'player1' ],
    "player2" => [25, 4, 'player2' ],
    "player3" => [35, 4, 'player3' ],
    "player4" => [45, 5, 'player4' ],
  };
$DB::single=1;
  $self->RunPSP(); $self->showAuction();
  $self->expect( {
      player1 => [  0,   0 ],
      player2 => [  5, 140 ],
      player3 => [ 15, 140 ],
      player4 => [ 45, 220 ],
    } );

  exit 0;
}

sub expect {
  my ($self,$expect) = @_;
  my ($player,$a,$c,$A,$C,$errors);
  $errors = 0;

  foreach $player ( keys %{$expect} ) {
    $A = $self->{bids}{$player}[ALLOCATION];
    $a = $expect->{$player}[0];
    if ( $A != $a ) {
      print "$player: found allocation = $A, expected $a\n";
      $errors++;
    }
    $C = $self->{bids}{$player}[COST];
    $c = $expect->{$player}[1];
    if ( $C != $c ) {
      print "$player: found cost = $C, expected $c\n";
      $errors++;
    }
  }
  die "\n *** Abort with $errors errors ***\n\n" if $errors;
  print "OK!\n\n";
}

1;