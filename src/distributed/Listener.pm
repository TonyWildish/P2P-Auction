package PSP::Listener;
use warnings;
use strict;
use POE;
use POE::Component::Server::HTTP;
use HTTP::Status qw / :constants / ;

# use Data::Dumper;
# $Data::Dumper::Terse=1;
# $Data::Dumper::Indent=0;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my ($self,$help,%params,%args,%pLower);
  %args = @_;

  %params = (
          Port           => undef,
          ContentHandler => undef,

          Verbose        => undef,
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

  $self->{alias} = POE::Component::Server::HTTP->new(
    Port           => $self->{Port},
    ContentHandler => { "/" => $self->ContentHandler() },
    ErrorHandler   => { "/" => $self->ErrorHandler() },
    Headers        => { Server => __PACKAGE__, },
  );

  return $self;
}

sub ContentHandler {
  my $self = shift;
  return sub {
    my ($request,$response) = @_;
    my $ret = POE::Kernel->call($self->{Alias},'ContentHandler',$request,$response);
    $self->{Verbose} && print "Listener: Got return-code ",$ret,"\n";
    return $ret;
  }
}

sub ErrorHandler {
  my $self = shift;
  return sub {
    my ($request,$response) = @_;
    my $ret = POE::Kernel->call($self->{Alias},'ErrorHandler',$request,$response);
    $self->{Verbose} && print "Listener: Got return-code ",$ret,"\n";
    return $ret;
  }
}

sub stop {
  my $self = shift;
  POE::Kernel->call($self->{alias}{http}, 'shutdown');
  POE::Kernel->call($self->{alias}{tcp},  'shutdown'); # Overkill, but hey...
  print "Ignore the 'Use of uninitialized value' warnings, if any...\n";
}

1;