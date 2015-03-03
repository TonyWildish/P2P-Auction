package PSP::Auctioneer;
use strict;
use warnings;

use HTTP::Status qw / :constants / ;
use base 'PSP::Util', 'PSP::Session';
use PSP::Listener;
use POE;
use JSON::XS;

# use Data::Dumper;
# $Data::Dumper::Terse=1;
# $Data::Dumper::Indent=0;

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
          Logfile       => undef,
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
          EqTimeout     =>  15, # How long with no bids before declaring equilibrium?
          Epsilon       =>   5, # bid-fee
          Q             => 100, # How much of whatever I'm selling
          WaitForBids   =>   5, # Wait to gather more bids after one is received
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

  if ( $self->{Logfile} && ! $self->{Pidfile} ) {
    $self->{Pidfile} = $self->{Logfile};
    $self->{Pidfile} =~ s%.log$%%;
    $self->{Pidfile} .= '.pid';
  }
  $self->daemon() if $self->{Logfile};

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

        SendAllocation  => 'SendAllocation',
        TriggerAuction  => 'TriggerAuction',
        StartAuction    => 'StartAuction',
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
  $self->StartListening();
}

sub hello {
  my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];

  defined($args->{url}) or die "No url defined in message\n";
  defined($args->{player}) or die "No player defined in message\n";
  $self->{urls}{$args->{player}} = $args->{url};
  $self->{players}{$args->{url}} = $args->{player};
  $self->Log('Hello from ',$args->{player},' (',$args->{url},')');
}

sub goodbye {
  my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];
  $self->Log('Goodbye handler...');
}

sub bid {
  my ($self,$kernel,$args,$player) = @_[ OBJECT, KERNEL, ARG0, ARG1 ];
  my ($p,$q);

  defined($p = $args->{p}) or die "No price defined in bid\n";
  defined($q = $args->{q}) or die "No quantity defined in bid\n";
  $self->Log("Bid from $player: (q=$q,p=$p)");

  $self->{bids}{$player} = [$q,$p];
  $kernel->yield('TriggerAuction');
# TW
  $self->{allocation}{$player} = [$q/2, $p+$self->{Epsilon}];
}

sub TriggerAuction {
  my ($self,$kernel) = @_[ OBJECT, KERNEL ];
  $self->Log("TriggerAuction");
  return if $self->{AuctionStarted};
  $self->{AuctionStarted} = 1;
  $kernel->delay_set('StartAuction',$self->{WaitForBids});
}

sub StartAuction {
  my ($self,$kernel) = @_[ OBJECT, KERNEL ];
  $self->Log("Starting auction!");
  foreach ( values %{$self->{players}} ) {
    $kernel->yield('SendAllocation',$_);
  }
}

sub SendAllocation {
  my ($self,$kernel,$player) = @_[ OBJECT, KERNEL, ARG0 ];
  my ($allocation,$cost);
  $allocation = $self->{allocation}{$player}[0];
  $cost       = $self->{allocation}{$player}[1];
  $self->Dbg('Allocate: ',$player,' (a=',$allocation,',c=',$cost,')');
  my $response = $self->get({
        api    => 'allocation',
        data   => $self->{allocation},
        target => $self->{urls}{$player} . $player . '/'
      });
  $self->Log('Allocate: ',$player,', (a=',$allocation,',c=',$cost,') OK');
  $self->{AuctionStarted} = 0;
}

1;