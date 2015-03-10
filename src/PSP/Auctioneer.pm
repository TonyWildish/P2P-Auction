package PSP::Auctioneer;
use strict;
use warnings;

use base 'PSP::Util';
use POE;

use Data::Dumper;
$Data::Dumper::Terse=1;
$Data::Dumper::Indent=0;

# Make the code more readable with named constants...
use constant QUANTITY   => 0;
use constant PRICE      => 1;
use constant PLAYER     => 2;
use constant ALLOCATION => 3;
use constant COST       => 4;

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

#         Parameters of the auction
          Epsilon        =>   5, # bid-fee
          Q              => 100, # How much of whatever I'm selling
          AuctionTimeout =>  10, # How long with no bids to declare auction over?
          BiddingTimeout =>   2, # How long after a bid before running an auction?

          POE_Trace      => 0,
          POE_Debug      => 0,
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
  $self->{LastRunPSPTime} = 0;

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

        hello           => 'hello',
        bid             => 'bid',

        SendOffer       => 'SendOffer',
        AuctionStart    => 'AuctionStart',
        AuctionEnded    => 'AuctionEnded',
      },
    ],
  )->option( trace => $self->{POE_Trace}, debug => $self->{POE_Debug} );;

  return $self;
}

# (re-)initialisation
sub start {
  my $self = shift;

  if ( $self->{Test} ) {
    $self->test();
    exit 0;
  }
}

# sub PostReadConfig {
#   my $self = shift;
# }

# handle interaction with players
sub hello {
  my ($self,$kernel,$player) = @_[ OBJECT, KERNEL, ARG0 ];

  $self->{players}{$player}++;
  $self->Log('Hello from ',$player);
  $kernel->post($player,'hello',{
      AuctionTimeout => $self->{AuctionTimeout},
      Epsilon        => $self->{Epsilon},
      Q              => $self->{Q},
    })
}

sub goodbye {
  my ($self,$kernel,$player) = @_[ OBJECT, KERNEL, ARG0 ];
  $self->Log('Goodbye from ',$player);
  delete $self->{players}{$player};
}

sub bid {
  my ($self,$kernel,$player,$args) = @_[ OBJECT, KERNEL, ARG0, ARG1 ];
  my ($p,$q,$t);

  defined($p = $args->{p}) or $self->ddie("No price defined in bid",$args);
  defined($q = $args->{q}) or $self->ddie("No quantity defined in bid",$args);
  $self->Log("Bid from $player: (q=$q,p=$p)");

  $self->{bids}{$player} = [ $q, $p, $player ];
  $self->{LastBidTime} = time();
  $kernel->delay_set('AuctionStart',$self->{BiddingTimeout});
}

sub AuctionStart {
  my ($self,$kernel) = @_[ OBJECT, KERNEL ];

  if ( $self->{LastBidTime} + $self->{BiddingTimeout} < time() ) {
    $self->Log("Too early to start the auction...");
    $kernel->delay_set('AuctionStart',1);
    return;
  }

  if ( $self->{LastBidTime} + $self->{BiddingTimeout} <=
       $self->{LastRunPSPTime}
     ) {
    return;
  }

  $self->{LastRunPSPTime} = time();
  $self->Log("Run the auction");
  $self->RunPSP();
  $kernel->yield('SendOffer','offer');

  if ( !$self->{AuctionTimer} ) {
    $self->Log("Set AuctionTimer");
    $self->{AuctionTimer} = $kernel->delay_set(
                              'AuctionEnded',
                              $self->{AuctionTimeout}
                            );
  }
}

sub AuctionEnded {
  my ($self,$kernel) = @_[ OBJECT, KERNEL ];

  if ( $self->{LastBidTime} + $self->{AuctionTimeout} > time() ) {
    $self->{AuctionTimer} = $kernel->delay_set('AuctionEnded',1);
    return;
  }

  $self->{AuctionTimer} = $self->{LastBidTime} = 0;
  $self->Log("Auction finished!");
  $kernel->call($self->{Me},'SendOffer','allocation');
  delete $self->{bids};
# TW  # delete $self->{allocation};
  print "\n";
}

sub SendOffer {
  my ($self,$kernel,$api) = @_[ OBJECT, KERNEL, ARG0 ];
  my ($allocation,$Api,$player,$a);
  $Api = ucfirst $api;

  foreach $player ( keys %{$self->{bids}} ) {
    $allocation->{$player} = {
      a => $self->{bids}{$player}[ALLOCATION],
      c => $self->{bids}{$player}[COST]
    };
  }
  foreach $player ( sort keys %{$allocation} ) {
    $a = $allocation->{$player};
    $kernel->post($player,$api,$allocation);
    $self->Log($Api,': ',$player,' (a=',$a->{a},',c=', $a->{c},')');
  }
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

  print "Auction results:\n Player: [ Qty, Bid, Alloc, Cost ]\n";
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
    $a->{$bid_i->[PLAYER]} = PSP::Util::min($Qi,$bid_i->[QUANTITY]);
  }
  return $a;
}

sub RunPSP {
  my ($self,$newbid) = @_;
  my ($bids,@bids,$Qi,$bid,$aj,$allocations);

  $self->{bids} = {} unless defined $self->{bids};
  $bids = $self->{bids};
  $bids->{$newbid->[PLAYER]} = $newbid if $newbid;

# Sort the bids by descending price-order
  @bids = sort { $b->[PRICE] <=> $a->[PRICE] }  values %{$bids};
  if ( $self->{Debug} ) {
    print "Sorted bids:\n";
    print map { '  [' . join(', ',@{$_}) . "]\n" } @bids;
  }

# Calculate the allocations for each player.
  $allocations = $self->Allocations(\@bids);
  map { $bids->{$_}[ALLOCATION] = $allocations->{$_} } keys %{$allocations};

# Now the quantities are allocated for all bids I can calculate the cost.
  foreach $bid ( @bids ) {
    $allocations = $self->Allocations(\@bids,$bid->[PLAYER]); # omit players in turn
    $bid->[COST] = 0;
    foreach ( keys %{$allocations} ) {
      next if $_ eq $bid->[PLAYER];
      next unless $bid->[ALLOCATION];
      $bid->[COST] += $bids->{$_}[PRICE] *
            ( $allocations->{$_} - $bids->{$_}[ALLOCATION] );
    }
    $bid->[COST] += $self->{Epsilon} if $bid->[ALLOCATION];
  }
}

sub test {
  my $self = shift;

  print "1) 1 bidder, should get everything at no cost\n";
  $self->RunPSP([70, 7, 'player1' ]); $self->showAuction();
  $self->expect( {
      player1 => [ 70, $self->{Epsilon} ],
    } );

  print "2) 2 bidders, not exceeding total Q\n";
  $self->{bids} = {
    "player1" => [70, 7, 'player1' ],
    "player2" => [30, 7, 'player2' ],
  };
  $self->RunPSP(); $self->showAuction();
  $self->expect( {
      player1 => [ 70, $self->{Epsilon} ],
      player2 => [ 30, $self->{Epsilon} ],
    } );

  print "3) 2 bidders, same price, exceeds total Q\n";
  $self->{bids} = {
    "player1" => [70, 4, 'player1' ],
    "player2" => [60, 4, 'player2' ],
  };
  $self->RunPSP(); $self->showAuction();
  $self->expect( {
      player1 => [ 40, 120 + $self->{Epsilon} ],
      player2 => [ 30, 120 + $self->{Epsilon} ],
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
      player4 => [ 10, 360 + $self->{Epsilon} ],
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

  print "6) 4 bidders, 3 with same price, exceeds total Q\n";
  $self->{bids} = {
    "player1" => [15, 4, 'player1' ],
    "player2" => [25, 4, 'player2' ],
    "player3" => [35, 4, 'player3' ],
    "player4" => [45, 5, 'player4' ],
  };
  $self->RunPSP(); $self->showAuction();
  $self->expect( {
      player1 => [  0,   0 ],
      player2 => [  5, 140 + $self->{Epsilon} ],
      player3 => [ 15, 140 + $self->{Epsilon} ],
      player4 => [ 45, 220 + $self->{Epsilon} ],
    } );

  print "7) 2 bidders, same price, exceeds total Q\n";
  $self->{bids} = {
    "player1" => [ 100,   5, 'player1' ],
    "player2" => [  60,   5, 'player2' ],
  };
  $self->RunPSP(); $self->showAuction();
  $self->expect( {
      player1 => [ 40, 300 + $self->{Epsilon} ],
      player2 => [  0,   0 ],
    } );

  # print "\n\n";
  # $self->{bids} = {};
  # $self->RunPSP([70,3,'player1']); $self->showAuction();
  # $self->RunPSP([60,6,'player2']); $self->showAuction();
  # $self->RunPSP([50,4,'player3']); $self->showAuction();
  # $self->RunPSP([40,5,'player4']); $self->showAuction();
  # $self->RunPSP([55,9,'player5']); $self->showAuction();
  # $self->RunPSP([80,3,'player6']); $self->showAuction();

  print "8) reproduce fig.4\n";
  $self->{bids} = {
    player1 => [ 100,  1, 'player1'],
    player2 => [  10,  2, 'player2'],
    player3 => [  20,  4, 'player3'],
    player5 => [  20,  7, 'player5'],
    player6 => [  30, 12, 'player6'],
  };
  $DB::single=1;
  print "price,quantity,utility,allocation,cost\n";
  my ($p,$q,$u);
  for ( $p=0; $p<=20; $p++ ) {
    for ( $q=0; $q<=100; $q+=5 ) {
      $self->RunPSP([$q,$p,'player4']);
      $u = 10 * $self->{bids}{player4}[ALLOCATION] - $self->{bids}{player4}[COST];
      print "$p,$q,$u,",$self->{bids}{player4}[ALLOCATION],',',$self->{bids}{player4}[COST],"\n";
    }
  }

  print "\n ** Congratulations, all tests passed! **\n\n";
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