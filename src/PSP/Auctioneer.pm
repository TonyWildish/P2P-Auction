package PSP::Auctioneer;
use strict;
use warnings;

use base 'PSP::Util';
use POE;
use POE::Queue::Array;
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
          Logfile       => undef,
          Pidfile       => undef,
          ConfigPoll    => 3,

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
  $self->ReadConfig(__PACKAGE__,$self->{Config});

  if ( $self->{Logfile} && ! $self->{Pidfile} ) {
    $self->{Pidfile} = $self->{Logfile};
    $self->{Pidfile} =~ s%.log$%%;
    $self->{Pidfile} .= '.pid';
  }
  $self->daemon() if $self->{Logfile};

  $self->{QUEUE} = POE::Queue::Array->new();

  POE::Session->create(
    object_states => [
      $self => {
        _start          => '_start',
        _default        => '_default',
        re_read_config  => 're_read_config',
      },
    ],
  );

  return $self;
}

sub _default {
  my ( $self, $kernel ) = @_[ OBJECT, KERNEL ];
  my $ref = ref($self);
  die <<EOF;

  Default handler for class $ref:
  The default handler caught an unhandled "$_[ARG0]" event.
  The $_[ARG0] event was given these parameters: @{$_[ARG1]}

  (...end of dump)
EOF
}

sub _start {
  my ( $self, $kernel, $session ) = @_[ OBJECT, KERNEL, SESSION ];
  $kernel->delay_set('re_read_config',$self->{ConfigPoll});
}

1;
