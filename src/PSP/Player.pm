package PSP::Player;
use strict;
use warnings;

use HTTP::Status qw / :constants / ;
use base 'PSP::Util', 'PSP::Session';
use PSP::Listener;
use POE;
use JSON::XS;
use LWP::UserAgent;

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
            'offer',
            'allocation',
          ],

          EqTimeout     => undef,  # How long with no bids before declaring equilibrium?
          Epsilon       => undef,  # bid-fee
          Q             => undef, # How much of whatever is being sold

          Strategy      => 'Random',
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
  die "No --name specified!\n" unless defined $self->{Me};
  $self->ReadConfig($self->{Me},$self->{Config});

  map { $self->{Handlers}{$_} = 1 } @{$self->{HandlerNames}};

  $self->{Strategies} = {
    'Random'        => 'StrategyRandom',
    'Fixed'         => 'StrategyFixed',
    'Interactive'   => 'StrategyInteractive',
    'Optimal'       => 'StrategyOptimal',
    'List'          => 'StrategyList',
  };

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

        SendHello       => 'SendHello',
        SendBid         => 'SendBid',
      },
    ],
  );

  return $self;
}

sub PostReadConfig {
  my $self = shift;
  return if $self->{Port} == $self->{CurrentPort};
  if ( $self->{Listening} ) {
    $self->Log('Port has changed, stop/start listening');
    $self->StopListening();
  }
  $self->{CurrentPort} = $self->{Port};

  my $strategy = $self->{Strategies}{$self->{Strategy}};
  if ( !defined($strategy) ) {
    die 'No handler for strategy ',$self->{Strategy},"\n";
  }
  $self->{StrategyHandler} = $self->can($strategy);

  $self->{MaxBids} = 5;
  if ( $self->{NBids} ) { $self->{MaxBids} = $self->{NBids}; }
  $self->{NBids} = $self->{MaxBids};

# Cheat by setting these from the config file.
# Should really ask the auctioneer for them instead...
  foreach ( qw / EqTimeout Epsilon Q / ) {
    $self->{$_} = $PSP::Auctioneer{$_};
  }
  $self->StartListening();

  $self->{server} = 'http://' .
                    $self->{AuctioneerHost} . ':' .
                    $self->{AuctioneerPort} . '/' .
                    $self->{Me} . '/';

  $self->Log($self->{Me},': Start bidding!');
  POE::Kernel->yield('SendHello');
}

sub SendHello {
  my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];
  my $data = {
      player => $self->{Me},
      url => 'http://' . $self->{Host} . ':' . $self->{Port} . '/'
    };
  my $response = $self->get( { api => 'hello', data => $data } );
  $self->Log('SendHello... OK');
  $self->Log('Start placing bids');
  $kernel->yield('SendBid');
}

# Handlers for the interaction with the auctioneer
sub hello {
  my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];
  # $self->Log('Hello handler...');
}

sub goodbye {
  my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];
  $self->Log('Goodbye handler...');
}

sub offer {
  my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];
  my $offer = $args->{$self->{Me}};
  $self->Log('Got offer: (a=',$offer->{q},',c=',$offer->{c},')');
  $kernel->delay_set('SendBid',rand()*1.5);
}

sub allocation {
  my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];
  my $offer = $args->{$self->{Me}};
  $self->Log('Got allocation: (a=',$offer->{q},',c=',$offer->{c},')');
  $kernel->delay_set('SendBid',10+3*rand());

  $self->{NBids} = int( rand() * $self->{MaxBids} ) + 1;
  print "\n";
}

# implement my own strategy
sub SendBid {
  my ($self,$kernel) = @_[ OBJECT, KERNEL ];
  my ($bid,$response,$strategy);

  if ( $self->{NBids}-- <= 0 ) {
    $self->Log("I'm happy now :-)") if $self->{NBids} == 0;
    return;
  }

  $bid = $self->{StrategyHandler}->($self);
  if ( !$bid ) {
    $self->Log('No more bids, now sit and wait...');
    return;
  }
  $response = $self->get({ api => 'bid', data => $bid });
  $self->Log('Bid: (q=',$bid->{q},',p=',$bid->{p},')',' (NBids = ',$self->{NBids},')');
}

# Strategies...
sub StrategyRandom {
  my $self = shift;
  my $bid = { q => int(rand($self->{Q})), p => int(rand(5)+3) };
  return $bid;
}

sub StrategyFixed {
  my $self = shift;
  my $bid = $self->{Bid};
  $bid = { q => 50, p => 10 } unless $bid;
  return $bid;
}

sub StrategyList {
  my $self = shift;
  my $bid = shift @{$self->{Bids}};
  return $bid;
}

sub StrategyInteractive {
  my $self = shift;
  my ($p,$q);
  print "q=?  > "; $q = <STDIN>; chomp($q);
  print "p=?  > "; $p = <STDIN>; chomp($p);
  print 'Read (q=',$q,',','p=',$p,")\n";
  return { q => $q, p => $p };
}

sub StrategyOptimal {
  my $self = shift;
  die "Strategy not implemented yet\n";
}

1;