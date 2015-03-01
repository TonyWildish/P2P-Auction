package PSP::Util;
use strict;
use warnings;
use POE;
use JSON::XS;

use Data::Dumper;
$Data::Dumper::Terse=1;
$Data::Dumper::Indent=0;

sub daemon {
  my ($self, $me) = @_;
  my $pid;

  # Open the pid file.
  open(PIDFILE, "> $self->{PIDFILE}")
      || die "$me: fatal error: cannot write to PID file ($self->{PIDFILE}): $!\n";
  $me = $self->{ME} unless $me;

  return if $self->{NODAEMON};

  # Fork once to go to background
  die "failed to fork into background: $!\n"
      if ! defined ($pid = fork());
  close STDERR if $pid; # Hack to suppress misleading POE kernel warning
  exit(0) if $pid;

  # Make a new session
  die "failed to set session id: $!\n"
      if ! defined setsid();

  # Fork another time to avoid reacquiring a controlling terminal
  die "failed to fork into background: $!\n"
      if ! defined ($pid = fork());
  close STDERR if $pid; # Hack to suppress misleading POE kernel warning
  exit(0) if $pid;

  # Clear umask
  # umask(0);

  # Write our pid to the pid file while we still have the output.
  ((print PIDFILE "$$\n") && close(PIDFILE))
      or die "$me: fatal error: cannot write to $self->{PIDFILE}: $!\n";

  # Indicate we've started
  print "$me: pid $$", ( $self->{DROPDIR} ? " started in $self->{DROPDIR}" : '' ), "\n";

  print "writing logfile to $self->{LOGFILE}\n";
  # Close/redirect file descriptors
  $self->{LOGFILE} = "/dev/null" if ! defined $self->{LOGFILE};
  open (STDOUT, ">> $self->{LOGFILE}")
      or die "$me: cannot redirect output to $self->{LOGFILE}: $!\n";
  open (STDERR, ">&STDOUT")
      or die "Can't dup STDOUT: $!";
  open (STDIN, "</dev/null");
  $|=1; # Flush output line-by-line
}

sub re_read_config {
  my ( $self, $kernel ) = @_[ OBJECT, KERNEL ];
  if ( defined($self->{mtime}) ) {
    my $mtime = (stat($self->{CONFIG}))[9];
    if ( $mtime > $self->{mtime} ) {
      $self->Logmsg("Config file has changed, re-reading...");
      $self->ReadConfig();
      $self->{mtime} = $mtime;
    }
  } else {
    $self->{mtime} = (stat($self->{CONFIG}))[9] or 0;
  }

  $kernel->delay_set('re_read_config',$self->{CONFIG_POLL});
}

sub ReadConfig {
  my $self = shift;

  $self->Logmsg("Reading config file $self->{CONFIG}");
  open CONFIG, "<$self->{CONFIG}" or die "Cannot open config file $self->{CONFIG}: $!\n";

  while ( <CONFIG> ) {
    next if m%^\s*#%;
    next if m%^\s*$%;
    s%#.*$%%;

    next unless m%\s*(\S+)\s*=\s*(\S+)\s*$%;
    $self->{uc $1} = $2;
  }
  close CONFIG;
}

1;
