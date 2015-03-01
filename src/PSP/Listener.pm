package PSP::Listener;
use warnings;
use strict;
use POE;
use POE::Component::Server::HTTP;
use HTTP::Status qw / RC_OK / ;

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
    ContentHandler => {"/" => \&web_handler },
    # ContentHandler => $self->{ContentHandler},
    Headers        => { Server => 'PSP::Listener', },
  );

  return $self;
}


sub web_handler {
  my ($request, $response) = @_;
  print "Got request for ",$request->{_uri}->path(),"\n";

  # Build the response.
  $response->code(RC_OK);
  $response->push_header("Content-Type", "text/plain");
  $response->content("That's all for now...\n\n");

  # Signal that the request was handled okay.
  return RC_OK;
}

1;
