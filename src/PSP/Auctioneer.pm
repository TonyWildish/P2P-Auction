package PSP::Auctioneer;
use strict;
use warnings;

use HTTP::Status qw / :constants / ;
use base 'PSP::Util', 'PSP::Session';
use PSP::Listener;
use POE;

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
          EqTimeout     => 15,  # How long with no bids before declaring equilibrium?
          Epsilon       =>  5,  # bid-fee
          Q             => 100, # How much of whatever I'm selling
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
        _child          => '_child',
        _default        => '_default',
        re_read_config  => 're_read_config',
        ContentHandler  => 'ContentHandler',
        ErrorHandler    => 'ErrorHandler',
        hello           => 'hello',
        goodbye         => 'goodbye',
        bid             => 'bid',
      },
    ],
  );

  return $self;
}

sub PostReadConfig {
  my $self = shift;
  return if $self->{Port} == $self->{CurrentPort};
  if ( $self->{Listening} ) {
    $self->Log("Port has changed, stop/start listening");
    $self->StopListening();
  }
  $self->{CurrentPort} = $self->{Port};
  $self->StartListening();
}

sub hello {
  my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];
  $self->Log("Hello handler...");
  my ($client,$player);
  defined($client = $args->{client}) or die "No client defined in message\n";
  defined($player = $args->{player}) or die "No player defined in message\n";
  $self->Log("Hello from '$client' (player: $player)");
  $self->{players}{$player} = $client;
}

sub goodbye {
  my ($self,$kernel,$args) = @_[ OBJECT, KERNEL, ARG0 ];
  $self->Log("Goodbye handler...");
}

sub bid {
  my ($self,$kernel,$args,$client) = @_[ OBJECT, KERNEL, ARG0, ARG1 ];
  $self->Log("Bid handler...");
  my ($p,$q);
  defined($p = $args->{p}) or die "No price defined in bid\n";
  defined($q = $args->{q}) or die "No quantity defined in bid\n";

  $self->Log("Client $client sent q=$q, p=$p");
}

1;