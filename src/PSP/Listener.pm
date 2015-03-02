package PSP::Listener;
use warnings;
use strict;
use POE;
use POE::Component::Server::HTTP;
use HTTP::Status qw / :constants / ;

sub new {
  my $proto = shift;
  my $class = ref($proto) || $proto;
  my ($self,$help,%params,%args,%pLower);
  %args = @_;

  %params = (
          Port => undef,
          ContentHandler => undef,
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

  POE::Component::Server::HTTP->new(
    Port           => $self->{Port},
    ContentHandler => { "/" => $self->handler() },
    Headers        => { Server => 'PSP::Listener', },
  );

  return $self;
}

sub handler {
  my $self = shift;
  return sub {
    my ($request,$response) = @_;
    my $ret = POE::Kernel->call($self->{Alias},'ContentHandler',$request,$response);
    print "Got return-code ",$ret,"\n";
    return $ret;
  }
}

1;
