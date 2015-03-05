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
        CollectingBids  => 'CollectingBids',
        AuctionStarted  => 'AuctionStarted',
        AuctionEnded    => 'AuctionEnded',
        Idle            => 'Idle',
      },
    ],
  );

  return $self;
}

# (re-)initialisation
sub start {
  my $self = shift;
  $self->Idle();
}

sub players {
  my $self = shift;
  my @players = keys %{$self->{bids}};
  return \@players;
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

  $t = time();
  $self->{bids}{$player} = [$q,$p,$t];
  $self->{LastBidTime} = $t;
  $kernel->yield('CollectingBids') if $self->{State} eq 'Idle';
}

# handle my own FSM
sub Idle {
  my ($self,$kernel) = @_[ OBJECT, KERNEL ];
  $self->Log('State: Idle');
  $self->{State} = 'Idle';
  $self->{AuctionEndTime} = 0;
  delete $self->{bids};
  delete $self->{allocation};

# TW
  print "\n";
}

sub CollectingBids {
  my ($self,$kernel) = @_[ OBJECT, KERNEL ];
  $self->Log('State: CollectingBids');
  $self->{State} = 'CollectingBids';
  $kernel->delay_set('AuctionStarted',$self->{TimeoutBids});
}

sub AuctionStarted {
  my ($self,$kernel) = @_[ OBJECT, KERNEL ];
  my ($player,$bid);
  $self->Log('State: AuctionStarted');
  $self->{State} = 'AuctionStarted';

  if ( $self->{bids} ) {
    $self->RunPSP();
    $kernel->yield('SendOffer','offer');
  }

# Set timer for switching to AuctionEnded state
  if ( ! $self->{AuctionRunning} ) {
    $self->{AuctionRunning} = 1;
    $kernel->delay_set('AuctionEnded',$self->{TimeoutAuction});
  }
}

sub AuctionEnded {
# Poll to see if the auction should be ended, or re-run
  my ($self,$kernel) = @_[ OBJECT, KERNEL ];

  if ( $self->{LastBidTime} >= $self->{LastRunTime} ) {
    $self->RunPSP();
    $kernel->yield('SendOffer','offer');
    $kernel->delay_set('AuctionEnded',2);
    return;
  }

  my $delta_t = time - $self->{LastRunTime};
  if ( $delta_t < $self->{TimeoutAuction} ) {
    $self->Log('State: AuctionEnded (no)');
    $kernel->delay_set('AuctionEnded',2);
  } else {
    $self->Log('State: AuctionEnded (yes)');
    $kernel->yield('SendOffer','allocation');
    $kernel->yield('Idle');
    $self->{State} = 'AuctionEnded';
    $self->{AuctionRunning} = 0;
  }
}

sub SendOffer {
  my ($self,$kernel,$api) = @_[ OBJECT, KERNEL, ARG0 ];
  my ($allocation,$cost,$Api,$player);
  $Api = ucfirst $api;
  foreach $player ( @{$self->players()} ) {
    next unless defined($self->{allocation}{$player} );
    $allocation = $self->{allocation}{$player}[0];
    $cost       = $self->{allocation}{$player}[1];
    $self->Dbg($Api,': ',$player,' (a=',$allocation,',c=',$cost,')');
    my $response = $self->get({
          api    => $api,
          data   => $self->{allocation},
          target => $self->{urls}{$player} . $player . '/'
        });
    $self->Log($Api,': ',$player,', (a=',$allocation,',c=',$cost,') OK');
  }
}

sub Q_ {
# $y is the bid-price being compared to
# $s is the player omitted from this strategy
  my ($self,$y,$s) = @_;
  my ($Q_,$player,$bid);
  $Q_ = $self->{Q};

# redundant...
  if ( $y < 0 ) { die "Q_ not defined for negative y ($y,$s)\n"; }  

  foreach $player ( @{$self->players()} ) {
    next if $player eq $s; # This means we loop over 's(-i)'
    next unless defined( $self->{bids}{$player} );
    $bid = $self->{bids}{$player};
    next unless $bid; print "Player=$player, ",Dumper($bid),"\n";
    next if $bid->[1] < $y;
    $Q_ -= $bid->[0];
  }
  if ( $Q_ < 0 ) { $Q_ = 0; }
  return $Q_;
}

sub allocation {
# $i is the player, if any, under active consideration
# $s is the player omitted from this strategy
  my ($self,$i,$s) = @_;
  my ($allocation,$p_i,$q_i,$Q_i);

  $p_i = 0;
  $p_i = $self->{bids}{$i}[1] if $i;

  $q_i = $self->{bids}{$s}[0];
  $Q_i = $self->Q_($p_i,$s);

  $allocation = $q_i < $Q_i ? $q_i : $Q_i;
  return $allocation;
}

sub cost {
  my ($self,$i) = @_;
  my ($cost,$p_j,$player);

  $cost = 0;
  foreach $player ( @{$self->players()} ) {
    next if $player eq $i;
    $p_j = $self->{bids}{$player}[1];
    $cost += $p_j *
             (
                $self->allocation( 0,$i) -
                $self->allocation($i,$i)
             )
  }
  return $cost;
}

sub RunPSP {
  my $self = shift;
  my ($player,$bid,$allocation,$cost);
# Here I calculate the allocations!
  $self->Log('RunPSP!');
  $self->{LastRunTime} = time();

  foreach $player ( @{$self->players()} ) {
    next unless defined($bid = $self->{bids}{$player});
    $self->Dbg('Player ',$player,' delta_t=',$self->{LastRunTime}-$bid->[2]);
    next if ( $bid->[2] < $self->{LastRunTime} &&
              defined($self->{allocation}{$player} ) );
    $allocation = $self->allocation($player,$player);
    $cost = $self->cost($player);
    $self->{allocation}{$player} = [$allocation, $cost+$self->{Epsilon}];
  }
}

1;