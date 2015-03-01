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
  my ($self,$help,%params,%args);
  %args = @_;
  map { $args{uc $_} = delete $args{$_} } keys %args;
  %params = (
          CONFIG    => undef,
          LOG       => undef,
          VERBOSE   => 0,
          DEBUG     => 0,
        );
  
  $self = \%params;
  bless $self, $class;

  if ( ! defined ($self->{CONFIG}=$args{CONFIG}) ) {
    die "No --config file specified!\n";
  }
  $self->ReadConfig();
  map { $self->{uc $_} = $args{$_} if $args{$_} } keys %args;
  if ( $self->{LOGFILE} && ! $self->{PIDFILE} ) {
    $self->{PIDFILE} = $self->{LOGFILE};
    $self->{PIDFILE} =~ s%.log$%%;
    $self->{PIDFILE} .= '.pid';
  }
  $self->daemon() if $self->{LOGFILE};

  $self->{QUEUE} = POE::Queue::Array->new();

  POE::Session->create(
    object_states => [
      $self => {
        re_read_config => 're_read_config',
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
  $kernel->delay_set('re_read_config',$self->{CONFIG_POLL});
}

1;
